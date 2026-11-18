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

class BusinessReportTest < ActiveSupport::TestCase
  Report = RedmineQboBilling::BusinessReport
  NOV = Date.new(2026, 11, 1)

  def report(data)
    full = { estimates: [], invoices: [], paid: [], payments: [], issues: [], time_entries: [] }.merge(data)
    Report.new(period: 'custom', from: NOV, to: NOV.end_of_month, today: Date.new(2026, 11, 20), data: full,
               previous_data: full.transform_values { [] })
  end

  def test_estimates_and_invoices_without_tax
    r = report(estimates: [[NOV + 1, '1080', 10, '80'], [NOV + 2, '500', 2]],
               invoices: [[NOV + 3, '1070', 5, '0', '70'], [NOV + 4, '200', 1, '200', '0']],
               payments: [[NOV + 5, '1070']])
    assert_equal BigDecimal('1500'), r.money[:estimates][:total]
    assert_equal BigDecimal('1200'), r.money[:invoices][:total]
    assert_equal BigDecimal('1270'), r.money[:invoices][:with_tax]
    assert_equal BigDecimal('200'), r.money[:invoices][:balance]
    assert_equal BigDecimal('1070'), r.money[:payments][:total]
    # $1,070 collected of $1,270 invoiced with tax
    assert_equal 84, r.ratios[:collected_of_invoiced]
    assert_equal 80, r.ratios[:invoiced_of_estimated]
  end

  def test_invoices_paid_in_full
    r = report(paid: [[NOV + 3, '1070', '70'], [NOV + 9, '500', nil]])
    assert_equal BigDecimal('1500'), r.money[:paid][:total]
    assert_equal 2, r.money[:paid][:count]
    november = r.months.find { |m| m[:month] == NOV }
    assert_equal BigDecimal('1500'), november[:paid]
    assert_equal 1500.0, r.chart[:current][:paid].compact.sum
  end

  def test_rows_missing_tax_are_unsynced
    r = report(estimates: [[NOV + 1, '100', 1, nil]], invoices: [[NOV + 1, '100', 1, '0', '0']])
    assert_equal 1, r.unsynced_count
  end

  def test_paid_badge_shows_the_day
    assert_equal 'Paid', RedmineQboBilling::InvoiceStatus.label(:paid)
    assert_match(/\APaid \S+/, RedmineQboBilling::InvoiceStatus.label(:paid, paid_on: Date.new(2026, 11, 3)))
    assert_equal 'Open', RedmineQboBilling::InvoiceStatus.label(:open, paid_on: Date.new(2026, 11, 3))
  end

  def test_taxes
    r = report(invoices: [[NOV + 3, '1070', 5, '0', '70'], [NOV + 4, '200', 1, '200', '0'], [NOV + 6, '535', 2, '0', '35']],
               paid: [[NOV + 9, '1070', '70'], [Date.new(2026, 11, 10), '500', nil]])
    assert_equal({ total: BigDecimal('105'), count: 2 }, r.taxes[:tax_invoiced])
    assert_equal({ total: BigDecimal('70'), count: 1 }, r.taxes[:tax_collected])
    november = r.months.find { |m| m[:month] == NOV }
    assert_equal BigDecimal('105'), november[:tax_invoiced]
    assert_equal BigDecimal('70'), november[:tax_collected]
    assert_equal 105.0, r.chart[:current][:tax_invoiced].compact.sum
    assert_equal 70.0, r.chart[:current][:tax_collected].compact.sum
  end

  def test_short_paid_badge
    status = RedmineQboBilling::InvoiceStatus
    nov18 = Date.new(2026, 11, 18)
    assert_equal 'Paid', status.short_label(:paid, paid_on: nov18, invoice_date: nov18)
    assert_equal 'Paid +1d', status.short_label(:paid, paid_on: nov18 + 1, invoice_date: nov18)
    assert_equal 'Paid +34d', status.short_label(:paid, paid_on: nov18 + 34, invoice_date: nov18)
    assert_equal 'Paid', status.short_label(:paid, paid_on: nil, invoice_date: nov18)
    # A deposit taken before the invoice: paid in full on its date
    assert_equal 'Paid', status.short_label(:paid, paid_on: nov18, invoice_date: nov18 + 2)
    assert_equal 'Open', status.short_label(:open, paid_on: nov18 + 3, invoice_date: nov18)
    assert_match(/\APaid in full \S+/, status.title(:paid, paid_on: nov18))
    assert_nil status.title(:open, paid_on: nov18)
  end
end
