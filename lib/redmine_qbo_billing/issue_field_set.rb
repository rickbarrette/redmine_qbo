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
  # The issue custom fields shown on the "Create issues from estimate" page.
  #
  # For every tracker the user may pick, a sample new issue is built in the target project to find
  # which custom fields the user can edit, and which are required (either the field's own
  # "Required" flag or a workflow rule for that tracker / role). Values are entered once on the page
  # and applied to every created issue whose tracker uses that field.
  class IssueFieldSet
    # File uploads can't be handled by this shared form
    UNSUPPORTED_FORMATS = %w[attachment].freeze

    Field = Struct.new(:custom_field, :custom_value, :tracker_ids, :required_tracker_ids, keyword_init: true) do
      def id
        custom_field.id
      end

      def required_for_any?
        required_tracker_ids.any?
      end
    end

    attr_reader :fields

    # values: the submitted { custom_field_id => value } hash, used to refill the form after errors
    def initialize(project:, trackers:, user: User.current, values: {})
      @fields = []
      by_id = {}

      Array(trackers).each do |tracker|
        issue = Issue.new(project: project, author: user)
        issue.tracker = tracker

        issue.editable_custom_field_values(user).each do |custom_value|
          custom_field = custom_value.custom_field
          next if UNSUPPORTED_FORMATS.include?(custom_field.field_format)

          field = by_id[custom_field.id] ||= Field.new(
            custom_field: custom_field,
            custom_value: custom_value,
            tracker_ids: [],
            required_tracker_ids: []
          )
          field.tracker_ids << tracker.id
          if custom_field.is_required? || issue.required_attribute?(custom_field.id.to_s, user)
            field.required_tracker_ids << tracker.id
          end
        end
      end

      @fields = by_id.values.sort_by { |f| [f.required_for_any? ? 0 : 1, f.custom_field.position.to_i] }

      values = (values || {}).to_h.transform_keys(&:to_s)
      @fields.each do |field|
        field.custom_value.value = values[field.id.to_s] if values.key?(field.id.to_s)
      end
    end

    def any?
      @fields.any?
    end
  end
end
