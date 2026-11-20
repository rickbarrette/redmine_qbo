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

class InvoiceStatusTest < ActiveSupport::TestCase
  Status = RedmineQboBilling::InvoiceStatus
  TODAY = Date.new(2026, 11, 20)

  def status(total, balance, due: nil)
    Status.status(total: total, balance: balance, due_date: due, today: TODAY)
  end

  def test_statuses
    assert_nil status(100, nil)
    assert_nil status(100, ' ')
    assert_equal :voided, status(0, 0)
    assert_equal :paid, status(100, 0)
    assert_equal :paid, status(100, -5)
    assert_equal :overdue, status(100, 40, due: TODAY - 1)
    assert_equal :partial, status(100, 40, due: TODAY)
    assert_equal :open, status(100, 100)
    assert_equal :open, status('100.00', '100')
  end

  def test_bad_numbers_count_as_zero
    assert_equal :voided, status('junk', '0')
    assert_equal BigDecimal('0'), Status.to_d('abc')
    assert_equal BigDecimal('0'), Status.to_d(nil)
  end

  def test_labels
    paid_on = Date.new(2026, 11, 3)
    assert_equal '', Status.label(nil)
    assert_equal I18n.t(:label_invoice_status_open), Status.label(:open)
    assert_equal I18n.t(:label_invoice_status_paid_on, date: I18n.l(paid_on)), Status.label(:paid, paid_on: paid_on)
    assert_equal I18n.t(:label_invoice_status_paid), Status.label(:paid)
  end

  def test_short_label_counts_days_to_pay
    assert_equal I18n.t(:label_invoice_status_paid_days, days: 3),
                 Status.short_label(:paid, paid_on: Date.new(2026, 11, 4), invoice_date: Date.new(2026, 11, 1))
    # Paid the same day (or before the invoice): just "Paid"
    assert_equal I18n.t(:label_invoice_status_paid),
                 Status.short_label(:paid, paid_on: Date.new(2026, 11, 1), invoice_date: Date.new(2026, 11, 1))
    assert_equal I18n.t(:label_invoice_status_open), Status.short_label(:open, paid_on: Date.new(2026, 11, 4), invoice_date: Date.new(2026, 11, 1))
  end

  def test_title_and_days
    assert_nil Status.title(:open, paid_on: TODAY)
    assert_nil Status.title(:paid)
    assert_equal I18n.t(:text_invoice_paid_in_full, date: I18n.l(TODAY)), Status.title(:paid, paid_on: TODAY)
    assert_nil Status.days_to_pay(nil, TODAY)
    assert_equal(-2, Status.days_to_pay(TODAY, TODAY - 2))
  end
end
