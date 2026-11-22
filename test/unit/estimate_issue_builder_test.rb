#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require File.expand_path('../test_helper', __dir__)

class EstimateIssueBuilderTest < ActiveSupport::TestCase
  include QboFakeServiceHelper
  fixtures :projects, :users, :email_addresses, :roles, :members, :member_roles, :issues, :issue_statuses, :trackers,
           :projects_trackers, :enabled_modules, :enumerations, :workflows, :custom_fields, :custom_values,
           :custom_fields_projects, :custom_fields_trackers, :issue_relations

  Builder = RedmineQboBilling::EstimateIssueBuilder

  def setup
    Setting.stubs(:plugin_redmine_qbo).returns('issue_default_tracker_id' => '2', 'issue_default_project_id' => '1')
    QboEstimateLineIssue.delete_all
    Estimate.where(id: 598).delete_all
    local_customer
    @estimate = Estimate.create!(id: 598, doc_number: '1068', customer_id: 9101)
    @estimate.stubs(:line_items).returns([
      qbo_sales_line(1, 10, 'Labor', 2, 120, description: 'Install lift kit'),
      qbo_sales_line(2, 11, 'Brake pads', 4, 30, description: 'Pads'),
      qbo_sales_line(3, 10, 'Labor', 0, 120, description: 'Diagnose noise'),
      qbo_sales_line(4, 10, 'Labor', 1, 120, description: '   ')
    ])
    @project = Project.find(1)
    @author = User.find(1)
    User.current = @author
  end

  def rows(*line_ids, **extra)
    line_ids.to_h { |id| [id.to_s, { 'selected' => '1', 'tracker_id' => '1' }.merge(extra.transform_keys(&:to_s))] }
  end

  def test_settings
    assert_equal 2, Builder.default_tracker_id
    assert_equal 1, Builder.default_project_id
  end

  def test_labor_hours
    assert_equal 3.0, Builder.labor_hours(@estimate)
    assert_equal 0.0, Builder.labor_hours(nil)
  end

  def test_proposals_are_labor_lines_with_a_description
    proposals = Builder.new(@estimate).proposals
    assert_equal %w[1 3], proposals.map(&:line_id)
    assert_equal ['Install lift kit', 2.0], [proposals.first.description, proposals.first.hours]
    assert_nil proposals.last.hours
    assert_not proposals.first.created?
    assert_equal [], Builder.new(nil).proposals
  end

  def test_create_issues
    builder = Builder.new(@estimate, defaults: { start_date: Date.new(2026, 11, 23), assignee: User.find(3) })
    created = builder.create_issues(project: @project, rows: rows(1, 3, estimated_hours: '1.5'), author: @author)
    assert_empty builder.errors
    # Subjects are title-cased by the issue patch
    assert_equal ['Install Lift Kit', 'Diagnose Noise'], created.map(&:subject)
    issue = created.first.reload
    assert_equal [598, 9101, 1.5, Date.new(2026, 11, 23)], [issue.estimate_id, issue.customer_id, issue.estimated_hours, issue.start_date]
    assert_match 'Estimate #1068', issue.description
    assert_equal 2, QboEstimateLineIssue.where(estimate_id: 598).count
    assert issue.relations.any? { |r| r.other_issue(issue) == created.last }

    # Shown as created; can't be made again
    again = Builder.new(@estimate)
    assert again.proposals.all?(&:created?)
    assert_equal [], again.create_issues(project: @project, rows: rows(1), author: @author)
    assert_equal [I18n.t(:error_no_estimate_lines_selected)], again.errors
  end

  def test_later_batches_are_related_to_earlier_ones
    first = Builder.new(@estimate).create_issues(project: @project, rows: rows(1), author: @author)
    second = Builder.new(@estimate).create_issues(project: @project, rows: rows(3), author: @author)
    assert IssueRelation.where(issue_from_id: [first.first.id, second.first.id], issue_to_id: [first.first.id, second.first.id]).exists?
  end

  def test_nothing_is_created_when_one_issue_fails
    builder = Builder.new(@estimate)
    count = Issue.count
    created = builder.create_issues(project: @project, rows: rows(1).merge(rows(3, tracker_id: '999')), author: @author)
    assert_equal [], created
    assert_equal count, Issue.count
    assert_match 'Diagnose noise', builder.errors.first
    assert_equal 0, QboEstimateLineIssue.count
  end

  def test_subject_and_default_description_overrides
    builder = Builder.new(@estimate, defaults: { description: 'From the appointment' })
    created = builder.create_issues(project: @project, rows: rows(1, subject: 'Custom subject'), author: @author)
    assert_equal 'Custom Subject', created.first.subject
    # The default description, then the line's parts (the brake pads follow the lift kit labor line)
    description = created.first.description.gsub("\r\n", "\n")
    assert description.start_with?("From the appointment\n")
    assert_match '4 × **Brake pads** — Pads', description
  end

  def test_unassignable_user_is_left_off
    outsider = User.find(7)
    created = Builder.new(@estimate, defaults: { assignee: outsider }).create_issues(project: @project, rows: rows(1), author: @author)
    assert_nil created.first.assigned_to
  end

  def test_subtasks_take_the_parents_customer
    parent = Issue.find(1)
    parent.update_column(:customer_id, 9102)
    created = Builder.new(@estimate, parent: parent).create_issues(project: @project, rows: rows(1), author: @author)
    issue = created.first.reload
    assert_equal parent.id, issue.parent_id
    assert_equal 9102, issue.customer_id
    # Not related to its own parent
    assert_not issue.relations.any? { |r| r.other_issue(issue) == parent }
  end

  def test_plugins_set_their_fields
    Redmine::Hook.expects(:call_hook).with(:qbo_billing_build_issue, has_key(:issue)).once
    Builder.new(@estimate).create_issues(project: @project, rows: rows(1), author: @author)
  end

  def test_relate_all_skips_existing_relations
    issues = Issue.where(id: [1, 2, 3]).order(:id).to_a
    IssueRelation.where(issue_from_id: [1, 2, 3]).or(IssueRelation.where(issue_to_id: [1, 2, 3])).delete_all
    IssueRelation.create!(issue_from: issues[0], issue_to: issues[1], relation_type: 'relates')
    assert_equal 2, Builder.relate_all(issues + [nil, issues[0]])
    assert_equal 0, Builder.relate_all(issues)
    assert_equal 0, Builder.relate_all([issues.first])
  end

  # ---- jobs: parts, notes and templates ----

  def estimate_with_jobs
    subtotal = qbo_subtotal_line
    @estimate.stubs(:line_items).returns([
      qbo_note_line(20, "Severe play in ball joints\nRecommend ball joints"),
      qbo_sales_line(21, 10, 'Labor', 4, 190, description: 'Install Ball Joints'),
      qbo_sales_line(22, 30, 'TF JL Ball Joints', 1, 300, description: "Ball joint kit\n3452010"),
      subtotal,
      qbo_sales_line(23, 31, 'Sales', 1, 315, description: 'Running boards'),
      qbo_sales_line(24, 10, 'Labor', 2, 190, description: 'Install side steps')
    ])
  end

  def template(key, description, note: '')
    RedmineQboBilling::IssueTemplateSupport::Option.new(
      key: key, title: key, tracker_id: 1, description: description,
      match_phrases: RedmineQboBilling::TemplateMatcher.phrases(note)
    )
  end

  def test_proposals_carry_their_job
    estimate_with_jobs
    builder = Builder.new(@estimate)
    proposal = builder.proposals.first
    assert_equal ['TF JL Ball Joints'], proposal.parts.map(&:item_name)
    assert_equal ['Running boards'], builder.proposals.last.parts.map(&:description)
    assert_not builder.ambiguous_parts?
  end

  def test_the_description_gets_the_estimate_notes_and_parts
    estimate_with_jobs
    RedmineQboBilling::IssueTemplateSupport.stubs(:find).returns(template('jl', 'Template body IAW Estimate #{{estimate}}'))
    created = Builder.new(@estimate).create_issues(project: @project, rows: rows(21, template: 'jl'), author: @author)
    description = created.first.reload.description
    assert description.start_with?('Template body IAW Estimate #1068')
    assert_match "Severe play in ball joints", description
    assert_match "1 × **TF JL Ball Joints** — Ball joint kit; 3452010", description
    assert_operator description.index('Template body'), :<, description.index('TF JL Ball Joints')
  end

  def test_a_template_can_place_the_notes_and_parts
    estimate_with_jobs
    body = "Findings:\n{{estimate_notes}}\n\nParts:\n{{estimate_parts}}\n\nEnd"
    RedmineQboBilling::IssueTemplateSupport.stubs(:find).returns(template('jl', body))
    description = Builder.new(@estimate).create_issues(project: @project, rows: rows(21, template: 'jl'), author: @author)
                         .first.reload.description.gsub("\r\n", "\n")
    assert_match(/\AFindings:\n.*Severe play.*\n\nParts:\n.*TF JL Ball Joints.*\n\nEnd\z/m, description)
    assert_no_match(/From the estimate/, description)
  end

  def test_the_default_description_gets_them_too
    estimate_with_jobs
    description = Builder.new(@estimate).create_issues(project: @project, rows: rows(24), author: @author).first.reload.description
    assert_match 'Estimate #1068', description
    assert_match 'Running boards', description
  end

  def test_nothing_is_added_when_a_job_has_no_notes_or_parts
    created = Builder.new(@estimate).create_issues(project: @project, rows: rows(3), author: @author)
    assert_no_match(/From the estimate/, created.first.reload.description)
  end

  def test_suggested_template_uses_the_line_and_its_parts
    estimate_with_jobs
    templates = [template('jk', 'JK', note: 'Match: ball joints, tf jk ball joints'),
                 template('jl', 'JL', note: 'Match: ball joints, tf jl ball joints'),
                 template('steps', 'Steps', note: 'Match: side steps, running boards')]
    builder = Builder.new(@estimate)
    assert_equal %w[jl steps], builder.proposals.map { |p| builder.suggested_template(p, templates)&.key }
  end

  def test_a_named_labor_service_uses_its_name
    Setting.stubs(:plugin_redmine_qbo).returns('labor_item_ids' => %w[10 40])
    @estimate.stubs(:line_items).returns([
      qbo_sales_line(30, 40, 'Standard Alignment', 1, 200, description: "• Load vehicle onto machine\n• Print out alignment")
    ])
    builder = Builder.new(@estimate)
    proposal = builder.proposals.first
    assert_equal 'Standard Alignment', proposal.description
    assert_equal ["• Load vehicle onto machine\n• Print out alignment"], proposal.notes
    templates = [template('align', 'Align', note: 'Match: standard alignment')]
    assert_equal 'align', builder.suggested_template(proposal, templates).key
  end
end
