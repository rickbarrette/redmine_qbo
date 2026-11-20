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

# BusinessReport's periods, chart points, hours and loading its figures from the database
class BusinessReportPeriodsTest < ActiveSupport::TestCase
  fixtures :projects, :users, :issues, :trackers, :issue_statuses, :enumerations, :time_entries

  Report = RedmineQboBilling::BusinessReport
  TODAY = Date.new(2026, 11, 20) # a Friday

  def range(period, **options)
    Report.range_for(period, today: TODAY, **options)
  end

  def test_periods
    assert_equal [Date.new(2026, 11, 16), Date.new(2026, 11, 22)], range('this_week')
    assert_equal [Date.new(2026, 11, 15), Date.new(2026, 11, 21)], range('this_week', week_start: :sunday)
    assert_equal [Date.new(2026, 11, 9), Date.new(2026, 11, 15)], range('last_week')
    assert_equal [Date.new(2026, 11, 1), Date.new(2026, 11, 30)], range('this_month')
    assert_equal [Date.new(2026, 10, 1), Date.new(2026, 10, 31)], range('last_month')
    assert_equal [Date.new(2026, 10, 1), Date.new(2026, 12, 31)], range('this_quarter')
    assert_equal [Date.new(2026, 7, 1), Date.new(2026, 9, 30)], range('last_quarter')
    assert_equal [Date.new(2025, 1, 1), Date.new(2025, 12, 31)], range('last_year')
    assert_equal [Date.new(2026, 1, 1), Date.new(2026, 12, 31)], range('this_year')
    assert_equal [Date.new(2026, 1, 1), Date.new(2026, 12, 31)], range('bogus')
  end

  def test_custom_period
    assert_equal [Date.new(2026, 3, 1), Date.new(2026, 4, 1)], range('custom', from: '2026-04-01', to: '2026-03-01')
    assert_equal [Date.new(2026, 1, 1), TODAY], range('custom', from: 'nope')
    assert_nil Report.parse_date('2026-13-01')
    assert_equal TODAY, Report.parse_date(TODAY)
  end

  def test_unknown_period_is_this_year
    assert_equal 'this_year', Report.new(period: 'forever', today: TODAY, data: {}).period
  end

  def test_week_start_setting
    assert_equal :sunday, Report.week_start_from_setting('7')
    assert_equal :saturday, Report.week_start_from_setting(6)
    assert_equal :monday, Report.week_start_from_setting('')
  end

  def report(period, **options)
    Report.new(period: period, today: TODAY, data: empty, previous_data: empty, **options)
  end

  def empty
    { estimates: [], invoices: [], paid: [], payments: [], issues: [], time_entries: [] }
  end

  def test_buckets_by_day_week_and_month
    week = report('this_week')
    assert_equal :day, week.granularity
    assert_equal 7, week.buckets.size

    month = report('this_month')
    assert_equal :week, month.granularity
    assert_equal [Date.new(2026, 11, 1), Date.new(2026, 11, 1)], month.buckets.first
    assert_equal [Date.new(2026, 11, 30), Date.new(2026, 11, 30)], month.buckets.last
    assert_equal [Date.new(2026, 11, 2) - 364, Date.new(2026, 11, 8) - 364], month.previous_buckets[1]

    year = report('this_year')
    assert_equal :month, year.granularity
    assert_equal 12, year.buckets.size
    assert_equal [Date.new(2025, 1, 1), Date.new(2025, 1, 31)], year.previous_buckets.first
  end

  def test_chart_stops_at_today
    r = Report.new(period: 'this_week', today: TODAY, data: empty.merge(payments: [[TODAY, '100']]), previous_data: empty)
    chart = r.chart
    assert_equal '2026-11-16', chart[:points].first
    assert_equal [0.0, 0.0, 0.0, 0.0, 100.0, nil, nil], chart[:current][:payments]
    assert_equal [0.0] * 7, chart[:previous][:payments]
  end

  def test_hours_cpi_and_ratios
    r = Report.new(period: 'this_month', today: TODAY, previous_data: empty,
                   data: empty.merge(estimates: [[TODAY, '0', 10]], invoices: [[TODAY, '0', 6, '0']],
                                     issues: [[TODAY, 8]], time_entries: [[TODAY, 7.5], [TODAY, 0.5]]))
    assert_equal({ estimate_hours: 10.0, issue_hours: 8.0, invoice_hours: 6.0, spent_hours: 8.0 }, r.hours)
    assert_equal 0.75, r.cpi
    assert_equal 75, r.ratios[:invoiced_of_spent]
    assert_equal 100, r.ratios[:spent_of_estimated]
    assert_nil r.ratios[:invoiced_of_estimated]
    november = r.months.last
    assert_equal [10.0, 8.0], november.values_at(:estimate_hours, :spent_hours)
  end

  def test_cpi_levels
    assert_nil Report.cpi(5, 0)
    assert_nil Report.cpi_level(nil)
    assert_equal :poor, Report.cpi_level(0.79)
    assert_equal :under, Report.cpi_level(0.95)
    assert_equal :good, Report.cpi_level(1.2)
  end

  def test_months_stop_at_the_current_month
    assert_equal (1..11).to_a, report('this_year').months.map { |m| m[:month].month }
    assert_equal [1], Report.new(period: 'custom', from: '2027-01-01', to: '2027-02-01', today: TODAY, data: empty)
                            .months.map { |m| m[:month].month }
  end

  def test_project_ids
    assert_not report('this_year').projects_filtered?
    filtered = report('this_year', project_ids: ['1', '0', 1, 'x'])
    assert_equal [1], filtered.project_ids
    assert filtered.projects_filtered?
  end

  def test_loads_figures_from_the_database
    Estimate.where(id: 9401).delete_all
    Invoice.where(id: [9501, 9502]).delete_all
    Payment.where(id: 9601).delete_all
    TimeEntry.delete_all
    Estimate.create!(id: 9401, doc_number: 'E1', customer_id: 1, txn_date: TODAY - 1, total_amount: 540, hours: 4, tax_amount: 40)
    Invoice.create!(id: 9501, doc_number: '1', customer_id: 1, txn_date: TODAY - 2, total_amount: 535, balance: 0,
                    hours: 3, tax_amount: 35, paid_on: TODAY - 1)
    Invoice.create!(id: 9502, doc_number: '2', customer_id: 1, txn_date: Date.new(2025, 11, 2), total_amount: 100, balance: 100)
    Payment.create!(id: 9601, customer_id: 1, txn_date: TODAY - 1, total_amount: 535)
    Issue.find(1).update_columns(created_on: TODAY.in_time_zone.change(hour: 9), estimated_hours: 5)
    Issue.find(5).update_columns(created_on: TODAY.in_time_zone.change(hour: 9), estimated_hours: 2)
    TimeEntry.new(issue_id: 1, project_id: 1, user_id: 2, author_id: 2, activity_id: 9, hours: 3.5, spent_on: TODAY).save!(validate: false)
    TimeEntry.new(issue_id: 5, project_id: 3, user_id: 2, author_id: 2, activity_id: 9, hours: 1, spent_on: TODAY).save!(validate: false)

    r = Report.new(period: 'this_month', today: TODAY)
    assert_equal({ total: BigDecimal('500'), count: 1 }, r.money[:estimates])
    assert_equal({ total: BigDecimal('500'), count: 1 }, r.money[:paid])
    assert_equal BigDecimal('535'), r.money[:payments][:total]
    assert_equal 1, r.money[:invoices][:count]
    assert_equal 7.0, r.hours[:issue_hours]
    assert_equal 4.5, r.hours[:spent_hours]
    assert_equal 0, r.unsynced_count

    only_one = Report.new(period: 'this_month', today: TODAY, project_ids: [1])
    assert_equal [5.0, 3.5], only_one.hours.values_at(:issue_hours, :spent_hours)
    # QuickBooks figures have no project
    assert_equal BigDecimal('535'), only_one.money[:payments][:total]
    # Last year's invoice is on the comparison line
    assert_equal 100.0, Report.new(period: 'this_month', today: TODAY).chart[:previous][:invoices].sum
  end
end
