#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module RedmineQbo
  # Capitalizes the first letter of every word and leaves the rest of each word exactly as typed,
  # so acronyms and model names survive: "led light bar for JL" -> "Led Light Bar For JL",
  # "LED" stays "LED", "4x4" stays "4x4", "(front)" -> "(Front)". Runs of whitespace become one space.
  # (Rails' titleize lowercases the rest of each word, turning "LED" into "Led" and "JL" into "Jl".)
  module TitleCase
    module_function

    def call(text)
      return text if text.nil?

      text.to_s.split(/\s+/).reject(&:empty?).map do |word|
        word.sub(/\A([^\p{L}\p{N}]*)(\p{Ll})/) { "#{Regexp.last_match(1)}#{Regexp.last_match(2).upcase}" }
      end.join(' ')
    end
  end
end
