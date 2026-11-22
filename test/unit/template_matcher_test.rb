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

# Picking an issue template from an estimate line's text and part names (RedmineQboBilling::TemplateMatcher)
class TemplateMatcherTest < ActiveSupport::TestCase
  Matcher = RedmineQboBilling::TemplateMatcher
  Option = RedmineQboBilling::IssueTemplateSupport::Option

  def option(key, note)
    Option.new(key: key, title: key, tracker_id: 1, match_phrases: Matcher.phrases(note))
  end

  def setup
    @templates = [
      option('jk', "Match: ball joints, tf jk ball joints, jk ball joints"),
      option('jl', "Match: ball joints, tf jl ball joints, jl ball joints, jt ball joints"),
      option('align', "Used for alignments\nmatch: standard alignment, alignment"),
      option('brakes', 'Match: front brakes, brake pads'),
      option('plain', 'Just a memo, no match line')
    ]
  end

  def test_phrases_come_from_a_match_line_in_the_note
    assert_equal ['standard alignment', 'alignment'], Matcher.phrases("Used for alignments\nMATCH: Standard Alignment,  alignment ,")
    assert_equal [], Matcher.phrases('No match line here')
    assert_equal [], Matcher.phrases(nil)
  end

  def test_the_longest_matching_phrase_wins
    assert_equal 'jl', Matcher.best(@templates, 'Install Ball Joints', 'TF JL Ball Joints').key
    assert_equal 'jk', Matcher.best(@templates, 'Replace Ball Joints', 'TF JK Ball Joints').key
  end

  def test_ties_go_to_the_first_template
    assert_equal 'jk', Matcher.best(@templates, 'Replace Ball Joints').key
  end

  def test_plurals_and_punctuation_still_match
    assert_equal 'brakes', Matcher.best(@templates, 'Replace front brake').key
    assert_equal 'brakes', Matcher.best(@templates, 'Brake-pads (front)').key
    assert_equal 'align', Matcher.best(@templates, 'STANDARD ALIGNMENT').key
  end

  def test_whole_words_only
    assert_nil Matcher.best(@templates, 'Misalignmentx')
  end

  def test_no_match
    assert_nil Matcher.best(@templates, 'Replace fuel filler')
    assert_nil Matcher.best([], 'Standard alignment')
  end
end
