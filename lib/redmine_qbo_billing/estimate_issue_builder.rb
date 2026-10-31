#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module RedmineQboBilling
  # Turns the labor lines of a QuickBooks estimate into proposed issues, and creates the ones the user selects
  # on the "Create issues from estimate" page (moved here from redmine_qbo_calendar).
  #
  # - Only lines with a labor product/service (LaborItems, e.g. "Labor") are proposed
  # - Subject = the line's description; estimated hours = the line's quantity
  # - Lines already turned into issues are shown but can't be created again
  # - Creation is all-or-nothing: if any issue fails validation, none are saved
  # - All issues created from the same estimate are related to each other, across batches
  #
  # Other plugins fill in more through hooks:
  #   :qbo_billing_issue_defaults, { estimate:, params: } => a hash of start_date, due_date, assignee,
  #     description, project, return_path, return_label, plus anything a plugin's own fields need (e.g.
  #     redmine_qbo_calendar's vehicle_id, when the page is opened from an appointment)
  #   :qbo_billing_build_issue, { issue:, estimate:, defaults: } for each new issue before it's saved, to set
  #     plugins' own fields (e.g. redmine_qbo_vehicles sets the vehicle)
  #   :qbo_billing_issues_created, { estimate:, issues:, params: } after issues are created
  class EstimateIssueBuilder
    include Redmine::I18n

    Proposal = Struct.new(:line_id, :item_name, :description, :hours, :existing_issue, keyword_init: true) do
      def created?
        existing_issue.present?
      end
    end

    def self.default_tracker_id
      setting('issue_default_tracker_id').to_i
    end

    def self.default_project_id
      setting('issue_default_project_id').to_i
    end

    def self.setting(key)
      (Setting.plugin_redmine_qbo || {})[key]
    rescue StandardError
      nil
    end

    # The estimate's labor hours: the quantities of its labor lines (LaborItems)
    # (e.g. for an appointment's hours, which shouldn't be less)
    def self.labor_hours(estimate)
      return 0.0 if estimate.nil?

      Array(estimate.line_items).sum do |line|
        detail = line.respond_to?(:sales_line_item_detail) ? line.sales_line_item_detail : nil
        next 0.0 if detail.nil? || !LaborItems.match?(detail.item_ref)
        detail.quantity.to_f
      end
    end

    # Relates every issue in the list to every other one ("Related to"), skipping pairs that already
    # have any relation. Used for issues created from the same estimate, whichever batch they came from.
    # Issues loaded fresh have no open journal, so this adds no history entries and sends no
    # "issue updated" emails. A failed relation (e.g. cross-project relations disabled) is logged, not fatal.
    # Returns the number of relations created.
    def self.relate_all(issues)
      issues = issues.compact.uniq(&:id)
      return 0 if issues.size < 2

      ids = issues.map(&:id)
      already_related = IssueRelation.where(issue_from_id: ids, issue_to_id: ids)
                                     .pluck(:issue_from_id, :issue_to_id)
                                     .map(&:minmax)
                                     .to_set

      issues.combination(2).count do |issue_from, issue_to|
        next false if already_related.include?([issue_from.id, issue_to.id].minmax)

        relation = IssueRelation.new(issue_from: issue_from, issue_to: issue_to,
                                     relation_type: IssueRelation::TYPE_RELATES)
        next true if relation.save

        Rails.logger.warn "[EstimateIssueBuilder] Could not relate ##{issue_from.id} and ##{issue_to.id}: " \
                          "#{relation.errors.full_messages.join(', ')}"
        false
      end
    end

    attr_reader :estimate, :defaults, :errors

    # estimate: redmine_qbo's local Estimate (its QuickBooks details give the lines)
    # defaults: start_date, due_date, assignee, description and plugins' own values (from :qbo_billing_issue_defaults)
    def initialize(estimate, defaults: {})
      @estimate = estimate
      @defaults = (defaults || {}).to_h.symbolize_keys
      @errors = []
    end

    def proposals
      @proposals ||= build_proposals
    end

    # rows: { line_id => { 'selected' => '1', 'subject' => ..., 'tracker_id' => ..., 'template' => 'global:3', 'estimated_hours' => ... } }
    # custom_field_values: { custom_field_id => value }, applied to every issue whose tracker uses the field
    # Returns the created issues, or [] with #errors filled in.
    def create_issues(project:, rows:, custom_field_values: {}, author: User.current)
      @errors = []
      rows = (rows || {}).to_h.transform_keys(&:to_s)

      selected = proposals.reject(&:created?).select { |p| rows.dig(p.line_id, 'selected') == '1' }
      if selected.empty?
        @errors << l(:error_no_estimate_lines_selected)
        return []
      end

      allowed_trackers = Issue.allowed_target_trackers(project, author).to_a

      built = selected.map do |proposal|
        [proposal, build_issue(proposal, rows[proposal.line_id] || {}, project, author, allowed_trackers, custom_field_values)]
      end

      Issue.transaction do
        built.each do |proposal, issue|
          next if issue.save

          @errors << "#{proposal.description.truncate(60)}: #{issue.errors.full_messages.join(', ')}"
        end
        raise ActiveRecord::Rollback if @errors.any?

        built.each do |proposal, issue|
          # Clear a link left behind by an issue that no longer exists, then record the new one
          QboEstimateLineIssue.where(estimate_id: estimate.id, line_id: proposal.line_id)
                              .where.not(issue_id: Issue.select(:id)).delete_all
          QboEstimateLineIssue.create!(estimate_id: estimate.id, line_id: proposal.line_id, issue: issue)
        end

        relate_issues(built.map(&:last))
      end

      @errors.any? ? [] : built.map(&:last)
    rescue ActiveRecord::RecordNotUnique, ActiveRecord::RecordInvalid
      # Someone else created issues from the same lines at the same moment
      @errors << l(:error_estimate_lines_already_created)
      []
    end

    private

    def build_proposals
      return [] if estimate.blank?

      ids = LaborItems.ids
      codes = LaborItems.codes
      links = QboEstimateLineIssue.where(estimate_id: estimate.id).includes(:issue).index_by(&:line_id)

      Array(estimate.line_items).each_with_index.filter_map do |line, index|
        detail = line.respond_to?(:sales_line_item_detail) ? line.sales_line_item_detail : nil
        next if detail.nil? || detail.item_ref.nil?

        item_name = detail.item_ref.name.to_s.strip
        next unless LaborItems.match?(detail.item_ref, ids: ids, codes: codes)

        # The subject comes from the line's description, so lines without one are skipped
        description = line.description.to_s.strip
        next if description.blank?

        line_id = line_key(line, index)
        quantity = detail.respond_to?(:quantity) ? detail.quantity.to_f : 0.0

        Proposal.new(
          line_id: line_id,
          item_name: item_name,
          description: description,
          hours: quantity.positive? ? quantity : nil,
          existing_issue: links[line_id]&.issue
        )
      end
    end

    # QBO line Ids are stable for the life of the estimate; fall back to line number / position
    def line_key(line, index)
      key = line.respond_to?(:id) ? line.id : nil
      key = line.line_num if key.blank? && line.respond_to?(:line_num)
      key = "pos-#{index}" if key.blank?
      key.to_s
    end

    # Relates the new issues to each other and to every issue created earlier from the same estimate.
    def relate_issues(new_issues)
      earlier = QboEstimateLineIssue.where(estimate_id: estimate.id)
                                    .where.not(issue_id: new_issues.map(&:id))
                                    .includes(:issue)
                                    .filter_map(&:issue)
      self.class.relate_all(earlier + new_issues)
    end

    def build_issue(proposal, row, project, author, allowed_trackers, custom_field_values)
      issue = Issue.new(project: project, author: author)
      issue.tracker = allowed_trackers.detect { |t| t.id == row['tracker_id'].to_i }

      # Shared custom field values. Going through safe_attributes means fields the tracker doesn't
      # use, or that this user can't edit (hidden / read-only by workflow), are ignored.
      if custom_field_values.present? && issue.tracker
        issue.send(:safe_attributes=, { 'custom_field_values' => custom_field_values.to_h }, author)
      end
      issue.subject = (row['subject'].presence || proposal.description).to_s.strip.truncate(255)

      template = IssueTemplateSupport.find(row['template'], project)
      issue.description = template&.description.presence || default_description

      hours = row.key?('estimated_hours') ? row['estimated_hours'] : proposal.hours
      issue.estimated_hours = hours.presence

      issue.start_date = defaults[:start_date] if defaults[:start_date]
      issue.due_date = defaults[:due_date] if defaults[:due_date]

      # Only assign someone who can be assigned in this project
      assignee = defaults[:assignee]
      issue.assigned_to = assignee if assignee && issue.assignable_users.include?(assignee)

      issue.customer_id = estimate.customer_id if issue.respond_to?(:customer_id=)
      issue.estimate_id = estimate.id if issue.respond_to?(:estimate_id=)

      # Plugins set their own fields (e.g. redmine_qbo_vehicles: the vehicle)
      Redmine::Hook.call_hook(:qbo_billing_build_issue, { issue: issue, estimate: estimate, defaults: defaults })

      issue
    end

    def default_description
      defaults[:description].presence ||
        "The purpose of this work is to bill the time spent on this issue for Estimate ##{estimate.doc_number}"
    end
  end
end
