#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module RedmineQbo
  # Fills {{name}} macros in an issue's subject and description (e.g. from an issue template:
  # "Estimate {{estimate}} for {{customer}}") when the issue is saved. Built in: {{customer}} and
  # {{estimate}}. Other plugins add their own through the :qbo_issue_macros hook (e.g.
  # redmine_qbo_vehicles' {{vehicle}}).
  #
  # A macro without a value yet (no estimate linked) stays as typed, so it fills on a later save.
  # Names nobody provides are left alone, which keeps Redmine's own wiki macros such as {{toc}} working.
  #
  # Issue notes are filled too (e.g. from a note template), when the note is saved or edited; see
  # Patches::JournalPatch. A note isn't saved again later, so a macro without a value stays as typed there.
  module IssueMacros
    PATTERN = /\{\{\s*([a-z][a-z0-9_]*)\s*\}\}/i
    FIELDS = %i[subject description].freeze

    module_function

    def fill(issue)
      texts = FIELDS.to_h { |field| [field, issue.send(field).to_s] }
      return unless texts.values.any? { |text| text.match?(PATTERN) }

      known = values(issue)
      return if known.empty?

      texts.each do |field, text|
        filled = substitute(text, known)
        issue.send("#{field}=", filled) unless filled == text
      end
    end

    # The text with this issue's macros filled in (e.g. a note); the text itself when there's nothing to fill
    def fill_text(issue, text)
      return text unless text.to_s.match?(PATTERN)

      known = values(issue)
      known.empty? ? text : substitute(text, known)
    end

    def substitute(text, known)
      text.gsub(PATTERN) { known[Regexp.last_match(1).downcase] || Regexp.last_match(0) }
    end

    # { 'name' => text } for every macro with a value for this issue
    def values(issue)
      found = {
        'customer' => issue.customer&.name,
        'estimate' => issue.estimate&.to_s
      }
      Redmine::Hook.call_hook(:qbo_issue_macros, { issue: issue }).each do |result|
        next unless result.is_a?(Hash)

        result.each { |name, value| found[name.to_s.downcase] = value }
      end
      found.transform_values { |value| value.to_s.strip.presence }.compact
    end
  end
end
