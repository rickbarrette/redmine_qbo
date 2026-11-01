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
  # Business figures for a date range, from the estimates, invoices and payments cached from QuickBooks and from
  # Redmine's issues and spent time:
  #   money: estimates written, invoices written, payments received (totals and counts)
  #   hours: man-hours on estimates, issues' estimated time, man-hours invoiced, time spent
  # with a month-by-month breakdown. Estimates, invoices and payments count by their QuickBooks date, issues by
  # the day they were created (only issues without subtasks, so parents' totals aren't counted twice), and
  # spent time by the day it was spent. project_ids limits the issues and spent time to those projects; the
  # QuickBooks figures have no project, so they always cover the whole business.
  class BusinessReport
    PERIODS = %w[this_week last_week this_month last_month this_quarter last_quarter this_year last_year custom].freeze
    WEEK_DAYS = { 1 => :monday, 6 => :saturday, 7 => :sunday }.freeze
    # Chart points: a day each for up to two weeks, a week each up to about three months, else a month each
    DAILY_UP_TO = 14
    WEEKLY_UP_TO = 93
    MONEY = %i[estimates invoices payments].freeze
    HOURS = %i[estimate_hours issue_hours invoice_hours spent_hours].freeze

    attr_reader :from, :to, :period, :project_ids

    # The dates for a period, from today: [from, to]. "custom" uses the given dates (either can be blank).
    def self.range_for(period, today: Date.current, from: nil, to: nil, week_start: :monday)
      case period.to_s
      when 'this_week'    then [today.beginning_of_week(week_start), today.end_of_week(week_start)]
      when 'last_week'    then w = today - 7; [w.beginning_of_week(week_start), w.end_of_week(week_start)]
      when 'this_month'   then [today.beginning_of_month, today.end_of_month]
      when 'last_month'   then m = today.prev_month; [m.beginning_of_month, m.end_of_month]
      when 'this_quarter' then [today.beginning_of_quarter, today.end_of_quarter]
      when 'last_quarter' then q = today.beginning_of_quarter.prev_month; [q.beginning_of_quarter, q.end_of_quarter]
      when 'last_year'    then y = today.prev_year; [y.beginning_of_year, y.end_of_year]
      when 'custom'
        f = parse_date(from) || today.beginning_of_year
        t = parse_date(to) || today
        f > t ? [t, f] : [f, t]
      else [today.beginning_of_year, today.end_of_year]
      end
    end

    def self.parse_date(value)
      return value if value.is_a?(Date)
      Date.iso8601(value.to_s) if value.present?
    rescue ArgumentError
      nil
    end

    # data (for tests): { estimates: [[date, total, hours]], invoices: [[date, total, hours, balance]],
    # payments: [[date, total]], issues: [[date, estimated_hours]], time_entries: [[date, hours]] }
    # week_start: the first day of a week (:monday, :saturday or :sunday); see week_start_from_setting.
    # previous_data (for tests): last year's data, like data.
    # project_ids: the projects whose issues and spent time count; blank for every project.
    def initialize(period: 'this_year', from: nil, to: nil, today: Date.current, data: nil, week_start: :monday,
                   previous_data: nil, project_ids: nil)
      @period = PERIODS.include?(period.to_s) ? period.to_s : 'this_year'
      @week_start = week_start
      @from, @to = self.class.range_for(@period, today: today, from: from, to: to, week_start: week_start)
      @today = today
      @data = data
      @previous_data = previous_data
      @project_ids = Array(project_ids).map(&:to_i).select(&:positive?).uniq
    end

    # Whether the issues and spent time are limited to some projects
    def projects_filtered?
      project_ids.any?
    end

    # Redmine's "Start calendars on" setting (1 Monday, 6 Saturday, 7 Sunday); Monday when it follows the language
    def self.week_start_from_setting(value)
      WEEK_DAYS[value.to_i] || :monday
    end

    # ---- charts ----

    # :day, :week or :month, from the length of the period
    def granularity
      days = (to - from).to_i + 1
      return :day if days <= DAILY_UP_TO
      days <= WEEKLY_UP_TO ? :week : :month
    end

    # The chart's points as [first day, last day] pairs covering the period
    def buckets
      @buckets ||= begin
        list = []
        case granularity
        when :day
          (from..to).each { |day| list << [day, day] }
        when :week
          start = from.beginning_of_week(@week_start)
          while start <= to
            list << [[start, from].max, [start + 6, to].min]
            start += 7
          end
        else
          start = from.beginning_of_month
          while start <= to
            list << [[start, from].max, [start.end_of_month, to].min]
            start = start.next_month
          end
        end
        list
      end
    end

    # The same points a year earlier. Days and weeks go back 52 weeks, so a Monday lines up with a Monday;
    # months go back to the same month.
    def previous_buckets
      @previous_buckets ||= if granularity == :month
                              buckets.map { |a, b| [a.prev_year, b.prev_year] }
                            else
                              buckets.map { |a, b| [a - 364, b - 364] }
                            end
    end

    # Everything the line charts need: the points' start dates, this period's figures per point (nil after
    # today, so the line stops there), and last year's for the same points (the toggle shows them).
    #   { granularity:, points: ["2026-10-26", ...],
    #     current: { estimates: [...], invoices:, payments:, estimate_hours:, issue_hours:, invoice_hours:, spent_hours: },
    #     previous: { same keys } }
    def chart
      current = sums_by_bucket(data, buckets)
      current.each_value { |values| buckets.each_with_index { |(a, _), i| values[i] = nil if a > @today } }
      {
        granularity: granularity,
        points: buckets.map { |a, _| a.iso8601 },
        ends: buckets.map { |_, b| b.iso8601 },
        previous_points: previous_buckets.map { |a, _| a.iso8601 },
        current: current,
        previous: sums_by_bucket(previous_data, previous_buckets)
      }
    end

    # Last year's data for the chart's points
    def previous_data
      @previous_data ||= load_data(previous_buckets.first[0], previous_buckets.last[1])
    end

    def data
      @data ||= load_data
    end

    # { estimates: { total:, count: }, invoices: { total:, count:, balance: }, payments: { total:, count: } }
    def money
      @money ||= {
        estimates: { total: money_sum(data[:estimates], 1), count: data[:estimates].size },
        invoices: { total: money_sum(data[:invoices], 1), count: data[:invoices].size, balance: money_sum(data[:invoices], 3) },
        payments: { total: money_sum(data[:payments], 1), count: data[:payments].size }
      }
    end

    # { estimate_hours:, issue_hours:, invoice_hours:, spent_hours: }
    def hours
      @hours ||= {
        estimate_hours: hour_sum(data[:estimates], 2),
        issue_hours: hour_sum(data[:issues], 1),
        invoice_hours: hour_sum(data[:invoices], 2),
        spent_hours: hour_sum(data[:time_entries], 1)
      }
    end

    # Cost performance index: invoiced hours / spent hours (e.g. 0.85), or nil without spent time. Below
    # CPI_WARNING (0.8) is poor, below 1 is under, 1 or more is on or over (more billed than worked).
    CPI_WARNING = 0.8

    def self.cpi(invoice_hours, spent_hours)
      spent = spent_hours.to_f
      spent.positive? ? (invoice_hours.to_f / spent).round(2) : nil
    end

    # :poor (below 0.8), :under (below 1) or :good (1 or more); nil without a CPI
    def self.cpi_level(cpi)
      return nil if cpi.nil?
      return :poor if cpi < CPI_WARNING
      cpi < 1 ? :under : :good
    end

    def cpi
      self.class.cpi(hours[:invoice_hours], hours[:spent_hours])
    end

    # Percentages comparing the figures (nil when there's nothing to compare against)
    def ratios
      {
        invoiced_of_estimated: percent(money[:invoices][:total], money[:estimates][:total]),
        collected_of_invoiced: percent(money[:payments][:total], money[:invoices][:total]),
        invoiced_of_spent: percent(hours[:invoice_hours], hours[:spent_hours]),
        spent_of_estimated: percent(hours[:spent_hours], hours[:issue_hours])
      }
    end

    # One row per month in the range, up to the current month: { month: Date (1st), estimates:, invoices:,
    # payments:, estimate_hours:, issue_hours:, invoice_hours:, spent_hours: }
    def months
      @months ||= begin
        rows = []
        month = from.beginning_of_month
        last = [to, @today].min
        last = from if last < from
        while month <= last
          rows << { month: month }.merge((MONEY + HOURS).index_with { |_| 0 })
          month = month.next_month
        end
        index = rows.index_by { |r| [r[:month].year, r[:month].month] }
        add = lambda do |list, key, col, kind|
          list.each do |row|
            r = index[[row[0].year, row[0].month]] or next
            r[key] += kind == :money ? to_d(row[col]) : row[col].to_f
          end
        end
        add.call(data[:estimates], :estimates, 1, :money)
        add.call(data[:invoices], :invoices, 1, :money)
        add.call(data[:payments], :payments, 1, :money)
        add.call(data[:estimates], :estimate_hours, 2, :hours)
        add.call(data[:issues], :issue_hours, 1, :hours)
        add.call(data[:invoices], :invoice_hours, 2, :hours)
        add.call(data[:time_entries], :spent_hours, 1, :hours)
        rows
      end
    end

    # Estimates and invoices in the range that synced before totals and hours were cached (a full sync fills them)
    def unsynced_count
      data[:estimates].count { |r| r[1].nil? || r[2].nil? } + data[:invoices].count { |r| r[1].nil? || r[2].nil? }
    end

    private

    # { money key or hours key => [sum per bucket] } for the data, in buckets ([first day, last day] pairs)
    def sums_by_bucket(rows, bucket_list)
      sums = (MONEY + HOURS).index_with { |_| Array.new(bucket_list.size, 0.0) }
      find = lambda do |date|
        bucket_list.index { |a, b| date >= a && date <= b }
      end
      columns = {
        estimates: [:estimates, 1], invoices: [:invoices, 1], payments: [:payments, 1],
        estimate_hours: [:estimates, 2], issue_hours: [:issues, 1], invoice_hours: [:invoices, 2], spent_hours: [:time_entries, 1]
      }
      columns.each do |key, (source, col)|
        Array(rows[source]).each do |row|
          i = find.call(row[0]) or next
          sums[key][i] += MONEY.include?(key) ? to_d(row[col]).to_f : row[col].to_f
        end
      end
      sums.transform_values { |values| values.map { |v| v.round(2) } }
    end

    def load_data(from = self.from, to = self.to)
      dates = from..to
      times = from.in_time_zone.beginning_of_day..to.in_time_zone.end_of_day
      leaf = "#{Issue.table_name}.rgt IS NULL OR #{Issue.table_name}.rgt - #{Issue.table_name}.lft = 1"
      issues = Issue.where(created_on: times).where(leaf).where.not(estimated_hours: nil)
      time_entries = TimeEntry.where(spent_on: dates)
      if projects_filtered?
        issues = issues.where(project_id: project_ids)
        time_entries = time_entries.where(project_id: project_ids)
      end
      {
        estimates: Estimate.where(txn_date: dates).pluck(:txn_date, :total_amount, :hours),
        invoices: Invoice.where(txn_date: dates).pluck(:txn_date, :total_amount, :hours, :balance),
        payments: Payment.where(txn_date: dates).pluck(:txn_date, :total_amount),
        issues: issues.pluck(:created_on, :estimated_hours).map { |t, h| [t.in_time_zone.to_date, h] },
        time_entries: time_entries.pluck(:spent_on, :hours)
      }
    end

    def money_sum(rows, col)
      rows.sum(BigDecimal('0')) { |r| to_d(r[col]) }
    end

    def hour_sum(rows, col)
      rows.sum(0.0) { |r| r[col].to_f }.round(2)
    end

    def to_d(value)
      BigDecimal(value.to_s.presence || '0')
    rescue ArgumentError
      BigDecimal('0')
    end

    def percent(part, whole)
      whole = whole.to_f
      return nil if whole <= 0
      (part.to_f / whole * 100).round
    end
  end
end
