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

class BillIssueTimeJobTest < ActiveSupport::TestCase
  include QboFakeServiceHelper
  fixtures :projects, :users, :members, :member_roles, :roles, :issues, :trackers, :projects_trackers,
           :issue_statuses, :enabled_modules, :enumerations, :time_entries

  # Stands in for QuickBooks' time activity and item services
  class FakeTimeService
    attr_reader :created
    attr_accessor :fail_on

    def initialize
      @created = []
    end

    def create(activity)
      raise Quickbooks::IntuitRequestException, 'QuickBooks is down' if fail_on && activity.hours.to_i == fail_on

      created << activity
      activity
    end
  end

  class FakeItemService
    attr_reader :queries

    def initialize(items)
      @items = items
      @queries = []
    end

    def query(sql)
      queries << sql
      name = sql[/Name = '(.*)'\z/, 1].to_s.gsub("\\'", "'")
      Array(@items[name])
    end
  end

  def setup
    local_customer
    @issue = Issue.find(1)
    @issue.update_columns(customer_id: 9101, assigned_to_id: 3, done_ratio: 40)
    User.find(3).update_column(:employee_id, 31)
    TimeEntry.delete_all
    @design = TimeEntryActivity.find(9)  # Design
    @dev = TimeEntryActivity.find(10)    # Development
    @times = FakeTimeService.new
    @items = FakeItemService.new('Design' => [Quickbooks::Model::Item.new(id: '5', unit_price: BigDecimal('90'))],
                                 'Development' => [Quickbooks::Model::Item.new(id: '6', unit_price: BigDecimal('120'))])
    Quickbooks::Service::TimeActivity.stubs(:new).returns(@times)
    Quickbooks::Service::Item.stubs(:new).returns(@items)
    qbo = Qbo.new(realm_id: '1')
    qbo.define_singleton_method(:perform_authenticated_request) { |&block| block.call('token') }
    QboConnectionService.stubs(:current!).returns(qbo)
    Qbo.stubs(:update_time_stamp)
  end

  def spend(activity, hours, billed: false)
    TimeEntry.create!(issue: @issue, project: @issue.project, user: User.find(2), activity: activity, hours: hours,
                      spent_on: Date.new(2026, 11, 18), billed: billed)
  end

  def test_sums_hours_by_activity_and_marks_them_billed
    first = spend(@design, 1.25)
    second = spend(@design, 0.5)
    third = spend(@dev, 2)
    spend(@dev, 3, billed: true)
    BillIssueTimeJob.perform_now(@issue.id)

    by_item = @times.created.to_h { |a| [a.item_ref.value, [a.hours, a.minutes]] }
    assert_equal({ '5' => [1, 45], '6' => [2, 0] }, by_item)
    activity = @times.created.first
    assert_equal ['31', '9101', 'Billable', 'Employee'], [activity.employee_ref.value.to_s, activity.customer_ref.value.to_s,
                                                          activity.billable_status, activity.name_of]
    assert_equal "#{@issue.tracker} ##{@issue.id}: #{@issue.subject} (Partial @ 40%)", activity.description
    assert [first, second, third].all? { |e| e.reload.billed }
  end

  def test_closed_issue_description_has_no_partial_note
    @issue.update_column(:status_id, IssueStatus.where(is_closed: true).first.id)
    spend(@design, 1)
    BillIssueTimeJob.perform_now(@issue.id)
    assert_equal "#{@issue.tracker} ##{@issue.id}: #{@issue.subject}", @times.created.first.description
  end

  def test_nothing_unbilled_does_nothing
    spend(@design, 1, billed: true)
    BillIssueTimeJob.perform_now(@issue.id)
    assert_empty @times.created
  end

  def test_activity_without_a_quickbooks_item_is_skipped_but_marked_billed
    @items = FakeItemService.new({})
    Quickbooks::Service::Item.stubs(:new).returns(@items)
    entry = spend(@design, 1)
    BillIssueTimeJob.perform_now(@issue.id)
    assert_empty @times.created
    assert entry.reload.billed
  end

  def test_a_failure_keeps_the_rest_for_a_retry
    design = spend(@design, 1)
    dev = spend(@dev, 2)
    @times.fail_on = 2
    assert_raises(Quickbooks::IntuitRequestException) { BillIssueTimeJob.new.perform(@issue.id) }
    assert design.reload.billed
    assert_not dev.reload.billed

    # The retry only sends what's left
    @times.fail_on = nil
    BillIssueTimeJob.new.perform(@issue.id)
    assert_equal [1, 2], @times.created.map(&:hours)
    assert dev.reload.billed
  end

  def test_item_names_are_quoted
    quoted = TimeEntryActivity.create!(name: "Tech's time", active: true)
    spend(quoted, 1)
    BillIssueTimeJob.perform_now(@issue.id)
    assert_equal "SELECT * FROM Item WHERE Name = 'Tech\\'s time'", @items.queries.last
  end
end
