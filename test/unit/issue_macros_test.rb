#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require File.expand_path('../test_helper', __dir__)

# {{customer}}, {{estimate}} and hooked macros in issue subjects and descriptions (RedmineQbo::IssueMacros)
class IssueMacrosTest < ActiveSupport::TestCase
  fixtures :projects, :users, :issues, :trackers, :issue_statuses, :enumerations, :journals

  CUSTOMER_ID = 9311
  ESTIMATE_ID = 9411

  class MacroHook < Redmine::Hook::Listener
    cattr_accessor :value

    def qbo_issue_macros(_context = {})
      value ? { 'Truck' => value } : nil
    end
  end

  def setup
    User.current = User.find(1)
    Estimate.where(id: ESTIMATE_ID).delete_all
    Customer.where(id: CUSTOMER_ID).delete_all
    @customer = Customer.new(id: CUSTOMER_ID, name: 'Jane Customer', phone_number: '555-0100')
    @customer.skip_qbo_push = true
    @customer.save!
    @estimate = Estimate.create!(id: ESTIMATE_ID, doc_number: '1068', customer_id: CUSTOMER_ID)
    @issue = Issue.find(1)
    @issue.update_columns(customer_id: nil, estimate_id: nil)
    MacroHook.value = nil
  end

  def teardown
    MacroHook.value = nil
  end

  def test_customer_and_estimate_fill_the_description
    @issue.description = "Estimate {{estimate}} for {{ Customer }}.\n{{toc}} {{unknown}}"
    @issue.customer = @customer
    @issue.estimate = @estimate
    assert @issue.save, @issue.errors.full_messages.join(', ')
    assert_equal "Estimate 1068 for Jane Customer.\r\n{{toc}} {{unknown}}", @issue.reload.description
  end

  def test_a_macro_without_a_value_waits_for_a_later_save
    @issue.description = 'Estimate {{estimate}} for {{customer}}'
    @issue.customer = @customer
    @issue.save!
    assert_equal 'Estimate {{estimate}} for Jane Customer', @issue.reload.description

    @issue.estimate = @estimate
    @issue.save!
    assert_equal 'Estimate 1068 for Jane Customer', @issue.reload.description
  end

  def test_the_subject_too
    @issue.subject = 'Work order {{estimate}}'
    @issue.estimate = @estimate
    @issue.save!
    assert_equal 'Work Order 1068', @issue.reload.subject
  end

  def test_other_plugins_add_macros_through_the_hook
    @issue.description = 'Inspect the {{truck}}'
    @issue.valid?
    assert_equal 'Inspect the {{truck}}', @issue.description

    MacroHook.value = '2018 Jeep Wrangler'
    @issue.valid?
    assert_equal 'Inspect the 2018 Jeep Wrangler', @issue.description
  end

  def test_text_without_macros_is_left_alone
    @issue.description = 'Nothing to fill'
    RedmineQbo::IssueMacros.expects(:values).never
    @issue.valid?
    assert_equal 'Nothing to fill', @issue.description
  end

  def test_a_new_note_is_filled_when_the_issue_is_saved
    @issue.estimate = @estimate
    @issue.customer = @customer
    @issue.save!
    @issue.init_journal(User.find(1), 'Called {{customer}} about estimate {{estimate}}')
    @issue.save!
    assert_equal 'Called Jane Customer about estimate 1068', @issue.journals.order(:id).last.notes
  end

  def test_a_note_uses_values_set_in_the_same_save
    @issue.init_journal(User.find(1), 'Estimate {{estimate}}')
    @issue.estimate = @estimate
    @issue.save!
    assert_equal 'Estimate 1068', @issue.journals.order(:id).last.notes
  end

  def test_an_edited_note_is_filled
    @issue.update_columns(customer_id: CUSTOMER_ID)
    journal = Journal.create!(journalized: @issue, user: User.find(1), notes: 'Plain note')
    journal.update!(notes: 'Spoke with {{customer}}')
    assert_equal 'Spoke with Jane Customer', journal.reload.notes
  end

  def test_a_note_macro_without_a_value_stays_as_typed
    journal = Journal.create!(journalized: @issue, user: User.find(1), notes: 'Estimate {{estimate}} and {{toc}}')
    assert_equal 'Estimate {{estimate}} and {{toc}}', journal.reload.notes
  end

  def test_hooked_macros_fill_notes
    MacroHook.value = '2018 Jeep Wrangler'
    journal = Journal.create!(journalized: @issue, user: User.find(1), notes: 'Test drove the {{truck}}')
    assert_equal 'Test drove the 2018 Jeep Wrangler', journal.reload.notes
  end
end
