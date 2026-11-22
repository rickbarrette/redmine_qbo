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
  # Adds an estimate's notes and a job's parts to a new issue's description (issues created from an estimate).
  #
  # A template can place them with {{estimate_notes}} and {{estimate_parts}}; otherwise they're added at the
  # end under "From the estimate". These are filled once, when the issue is created: later saves can't see
  # the estimate's lines (unlike redmine_qbo's issue macros such as {{estimate}}).
  module EstimateIssueDetails
    NOTES = /\{\{\s*estimate_notes\s*\}\}/i
    PARTS = /\{\{\s*estimate_parts\s*\}\}/i

    module_function

    def apply(text, notes:, parts:)
      text = text.to_s
      notes_text = notes_markdown(notes)
      parts_text = parts_markdown(parts)
      placed = text.match?(NOTES) || text.match?(PARTS)

      text = text.gsub(NOTES) { notes_text }.gsub(PARTS) { parts_text }
      return text if placed

      sections = []
      sections << "**#{I18n.t(:label_estimate_issue_notes)}**\n\n#{notes_text}" if notes_text.present?
      sections << "**#{I18n.t(:label_estimate_issue_parts)}**\n\n#{parts_text}" if parts_text.present?
      return text if sections.empty?

      [text.rstrip, '---', "### #{I18n.t(:label_estimate_issue_details)}", *sections].reject(&:empty?).join("\n\n")
    end

    # Each note as a quote, its lines kept
    def notes_markdown(notes)
      Array(notes).map { |note| note.to_s.strip.lines.map { |l| "> #{l.rstrip}" }.join("\n") }.reject(&:empty?).join("\n>\n")
    end

    # "* 2 × **Item** — description; part number"
    def parts_markdown(parts)
      Array(parts).map do |part|
        description = part.description.to_s.lines.map(&:strip).reject(&:empty?).join('; ')
        line = "* #{part.quantity.presence || 1} × **#{part.item_name.presence || '—'}**"
        description.present? ? "#{line} — #{description}" : line
      end.join("\n")
    end
  end
end
