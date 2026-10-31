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
  # The work orders (Redmine issues) behind an estimate or invoice, and the two hooks other plugins use with
  # them:
  #
  # :qbo_billing_issue_values, { issues: [Issue, ...] }
  #   Return a hash of field => { issue_id => value }, e.g. redmine_qbo_vehicles returns
  #   { vin: { 116 => "1C4HJXDG5JW123456" }, mileage: { 116 => "48210" } } (mileage from the issue custom
  #   field named "Mileage"). The invoice's VIN and mileage boxes are filled from them when time or
  #   estimates are imported (the highest mileage wins).
  #
  # :qbo_billing_validate, { document: "invoice" or "estimate", form: EstimateForm, issues: [Issue, ...] }
  #   Return an error message (or a list of them) to stop the save, e.g. redmine_qbo_vehicles refuses an
  #   invoice whose work orders are for more than one vehicle. Return nil to allow it.
  module IssueValues
    # The issue a line came from: redmine_qbo writes "Install #116: some job" on time activities, and
    # redmine_qbo_lineitems starts its estimates with "Added from: Install #116: some job"
    ISSUE_REFERENCE = /#(\d+):/
    ADDED_FROM = /\A\s*Added from:/i

    module_function

    def issue_reference(text)
      text.to_s.lines.first.to_s[ISSUE_REFERENCE, 1]
    end

    # Issues behind the document: the ones its time lines and "Added from" notes name, and the ones linked
    # to its estimates (an invoice's linked estimates, or the estimate itself)
    def issue_ids(form)
      ids = form.filled_lines.filter_map do |line|
        next if line.subtotal?
        issue_reference(line.description) if line.time_activity_id.present? || line.description.to_s.match?(ADDED_FROM)
      end
      estimate_ids = Array(form.linked_estimate_ids).dup
      estimate_ids << form.id if !form.invoice? && form.persisted?
      ids += Issue.where(estimate_id: estimate_ids.map(&:to_s)).pluck(:id).map(&:to_s) if estimate_ids.any?
      ids.map(&:to_s).uniq
    end

    def issues(form)
      ids = issue_ids(form)
      ids.empty? ? [] : Issue.where(id: ids).to_a
    end

    # { vin: { "116" => "..." }, mileage: { "116" => "..." } } from every plugin listening
    def values_for(issues)
      issues = Array(issues)
      return {} if issues.empty?

      Redmine::Hook.call_hook(:qbo_billing_issue_values, { issues: issues }).each_with_object({}) do |result, merged|
        next unless result.is_a?(Hash)
        result.each do |field, by_issue|
          next unless by_issue.is_a?(Hash)
          (merged[field.to_sym] ||= {}).merge!(by_issue.transform_keys(&:to_s).transform_values(&:to_s).reject { |_, v| v.strip.empty? })
        end
      end
    end

    # The same values by issue, for the import panel: { "116" => { vin: "...", mileage: "..." } }
    def by_issue(issues)
      values_for(issues).each_with_object({}) do |(field, by_id), result|
        by_id.each { |id, value| (result[id] ||= {})[field] = value }
      end
    end

    # Error messages from plugins that want this save stopped
    def plugin_errors(form)
      context = { document: form.document, form: form, issues: issues(form) }
      Redmine::Hook.call_hook(:qbo_billing_validate, context).flatten.compact.map(&:to_s).reject(&:empty?)
    rescue StandardError => e
      Rails.logger.warn "[RedmineQboBilling] A plugin's validation failed: #{e.message}"
      []
    end
  end
end
