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

class IssueValuesTest < ActiveSupport::TestCase
  fixtures :projects, :users, :issues, :trackers, :issue_statuses, :enumerations

  Values = RedmineQboBilling::IssueValues
  Form = RedmineQboBilling::EstimateForm

  def form(lines, attrs = {})
    Form.new({ lines: lines.map { |l| Form::Line.new(l) } }.merge(attrs))
  end

  def test_issue_reference_reads_the_first_line
    assert_equal '116', Values.issue_reference("Install #116: lift kit\nmore #200: text")
    assert_nil Values.issue_reference('no reference')
    assert_nil Values.issue_reference(nil)
  end

  def test_issue_ids_from_time_lines_added_from_notes_and_linked_estimates
    Issue.find(3).update_column(:estimate_id, 777)
    doc = form([{ description: 'Install #1: lift', time_activity_id: '55', rate: '1' },
                { description: 'Added from: Repair #2: brakes' },
                { description: 'Mentions #5: but not imported', rate: '1' },
                { description: 'Subtotal #6: x', kind: 'subtotal', time_activity_id: '9' }],
               document: 'invoice', linked_estimate_ids: ['777'])
    assert_equal %w[1 2 3], Values.issue_ids(doc).sort
    assert_equal [1, 2, 3], Values.issues(doc).map(&:id).sort
  end

  def test_saved_estimate_counts_its_own_issues
    Issue.find(4).update_column(:estimate_id, 888)
    assert_equal ['4'], Values.issue_ids(form([], id: '888'))
    assert_equal [], Values.issue_ids(form([]))
    assert_equal [], Values.issues(form([]))
  end

  def test_values_merge_plugins_and_drop_blanks
    Redmine::Hook.stubs(:call_hook).with(:qbo_billing_issue_values, anything)
                 .returns([{ 2 => { 1 => 'VIN1', 2 => ' ' } }, 'junk', { '2' => { 3 => 'VIN3' }, '4' => 'not a hash' }])
    issues = Issue.where(id: [1, 2, 3]).to_a
    assert_equal({ '2' => { '1' => 'VIN1', '3' => 'VIN3' } }, Values.values_for(issues))
    assert_equal({ '1' => { '2' => 'VIN1' }, '3' => { '2' => 'VIN3' } }, Values.by_issue(issues))
    assert_equal({}, Values.values_for([]))
  end

  def test_plugin_errors
    Redmine::Hook.stubs(:call_hook).with(:qbo_billing_validate, has_entries(document: 'invoice'))
                 .returns([['Two vehicles', nil], '', 'Other'])
    assert_equal ['Two vehicles', 'Other'], Values.plugin_errors(form([], document: 'invoice'))
  end

  def test_a_failing_plugin_does_not_stop_the_save
    Redmine::Hook.stubs(:call_hook).raises(StandardError, 'boom')
    assert_equal [], Values.plugin_errors(form([]))
  end
end
