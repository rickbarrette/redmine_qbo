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
  # Picks the issue template for an estimate line. A template opts in with a line in its note
  # (redmine_issue_templates' "Note" field), e.g.
  #
  #   Match: ball joints, tf jl ball joints, jl ball joints
  #
  # The line's text and its parts' product names are searched for each phrase (whole words, ignoring
  # case, punctuation and plural "s"). The template with the longest phrase found wins, so
  # "TF JL Ball Joints" beats "ball joints"; on a tie, the first template in the list.
  module TemplateMatcher
    MATCH_LINE = /^\s*match\s*:\s*(.+)$/i

    module_function

    # The phrases from a template's note
    def phrases(note)
      line = note.to_s.lines.map { |l| l.match(MATCH_LINE) }.compact.first
      return [] unless line

      line[1].split(',').map { |phrase| phrase.strip.downcase }.reject(&:empty?).uniq
    end

    # templates: IssueTemplateSupport options (with match_phrases); texts: the line's description, part names...
    def best(templates, *texts)
      haystack = " #{normalize(texts.flatten.compact.join(' '))} "
      return nil if haystack.strip.empty?

      best, best_length = nil, 0
      Array(templates).each do |template|
        Array(template.match_phrases).each do |phrase|
          words = normalize(phrase)
          next if words.empty? || words.length <= best_length
          next unless haystack.include?(" #{words} ")

          best, best_length = template, words.length
        end
      end
      best
    end

    # Lower case words without punctuation or a plural "s"
    def normalize(text)
      text.to_s.downcase.scan(/[a-z0-9]+/).map { |word| word.length > 3 ? word.sub(/s\z/, '') : word }.join(' ')
    end
  end
end
