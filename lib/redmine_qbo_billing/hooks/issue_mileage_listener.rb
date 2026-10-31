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
  module Hooks

    # Each work order's mileage, from Redmine's own issue custom field named "Mileage" (any capitalisation),
    # so an invoice's mileage box fills in when its time or estimates are imported. Answers the same
    # qbo_billing_issue_values hook other plugins use (see IssueValues).
    class IssueMileageListener < Redmine::Hook::Listener

      def qbo_billing_issue_values(context = {})
        issue_ids = Array(context[:issues]).map(&:id)
        field = IssueCustomField.all.detect { |f| f.name.to_s.strip.casecmp?('mileage') }
        return {} if field.nil? || issue_ids.empty?

        values = CustomValue.where(customized_type: 'Issue', customized_id: issue_ids, custom_field_id: field.id)
                            .where.not(value: [nil, ''])
                            .pluck(:customized_id, :value)
        { mileage: values.to_h }
      end

    end
  end
end
