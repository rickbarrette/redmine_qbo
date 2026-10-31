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
  # spent time by the day it was spent.
  class BusinessReport
    PERIODS = %w[this_month last_month this_quarter last_quarter this_year last_year custom].freeze
    MONEY = %i[estimates invoices payments].freeze
    HOURS = %i[estimate_hours issue_hours invoice_hours spent_hours].freeze

    attr_reader :from, :to, :period

    # The dates for a period, from today: [from, to]. "custom" uses the given dates (either can be blank).
    def self.range_for(period, today: Date.current, from: nil, to: nil)
      case period.to_s
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
    def initialize(period: 'this_year', from: nil, to: nil, today: Date.current, data: nil)
      @period = PERIODS.include?(period.to_s) ? period.to_s : 'this_year'
      @from, @to = self.class.range_for(@period, today: today, from: from, to: to)
      @today = today
      @data = data
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

    def load_data
      dates = from..to
      times = from.in_time_zone.beginning_of_day..to.in_time_zone.end_of_day
      leaf = "#{Issue.table_name}.rgt IS NULL OR #{Issue.table_name}.rgt - #{Issue.table_name}.lft = 1"
      {
        estimates: Estimate.where(txn_date: dates).pluck(:txn_date, :total_amount, :hours),
        invoices: Invoice.where(txn_date: dates).pluck(:txn_date, :total_amount, :hours, :balance),
        payments: Payment.where(txn_date: dates).pluck(:txn_date, :total_amount),
        issues: Issue.where(created_on: times).where(leaf).where.not(estimated_hours: nil)
                     .pluck(:created_on, :estimated_hours).map { |t, h| [t.in_time_zone.to_date, h] },
        time_entries: TimeEntry.where(spent_on: dates).pluck(:spent_on, :hours)
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
