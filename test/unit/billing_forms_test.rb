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

# PaymentForm, RefundForm and InvoiceRefundForm
class BillingFormsTest < ActiveSupport::TestCase
  def payment(attrs = {})
    RedmineQboBilling::PaymentForm.from_params({ 'customer_id' => '9101', 'txn_date' => '2026-11-20',
                                                 'payment_method_id' => '2', 'amount' => '$1,000' }.merge(attrs))
  end

  def test_payment_form_from_params
    form = payment('invoice_ids' => ['7', '', '7', '8'], 'sync_token' => '3', 'deposit' => '1')
    assert_equal %w[7 8], form.invoice_ids
    assert_equal '3', form.sync_token
    assert_equal BigDecimal('1000'), form.amount_value
    assert_equal Date.new(2026, 11, 20), form.txn_date_value
    assert form.deposit?
    assert_not form.persisted?
    assert RedmineQboBilling::PaymentForm.from_params({}, id: '12').persisted?
    assert_equal [], RedmineQboBilling::PaymentForm.new.invoice_ids
  end

  def test_payment_form_validation
    assert payment.valid?
    form = RedmineQboBilling::PaymentForm.from_params({ 'amount' => '0', 'txn_date' => 'x' })
    assert_not form.valid?
    assert_includes form.errors[:base], I18n.t(:error_estimate_needs_customer)
    assert_includes form.errors[:base], I18n.t(:error_payment_needs_method)
    assert_includes form.errors[:base], I18n.t(:error_payment_amount)
    assert_includes form.errors[:base], I18n.t(:error_estimate_field_invalid, field: I18n.t(:label_payment_date))
    assert_not payment('amount' => 'abc').valid?
    assert_not payment('amount' => '-5').valid?
  end

  def refund(attrs = {})
    RedmineQboBilling::RefundForm.from_params({ 'customer_id' => '9101', 'txn_date' => '2026-11-20',
                                                'method' => 'card', 'reason' => 'Canceled order' }.merge(attrs))
  end

  def test_refund_form
    form = refund('parts_amount' => '307.99', 'close_estimate' => '1', 'cancel_issues' => '0')
    assert form.valid?, form.errors.full_messages.inspect
    assert_equal BigDecimal('307.99'), form.parts_value
    assert form.close_estimate?
    assert_not form.cancel_issues?
    assert_not form.email_customer?
    assert_not form.check?
    assert_equal BigDecimal('0'), refund.parts_value
  end

  def test_refund_form_validation
    form = RedmineQboBilling::RefundForm.from_params('method' => 'check', 'parts_amount' => '-1')
    assert_not form.valid?
    %i[error_estimate_needs_customer error_refund_check_number error_refund_reason error_refund_parts_amount].each do |key|
      assert_includes form.errors[:base], I18n.t(key)
    end
    assert_includes refund('method' => 'cash').tap(&:valid?).errors[:base], I18n.t(:error_refund_method)
    assert_includes refund('parts_amount' => 'lots').tap(&:valid?).errors[:base], I18n.t(:error_refund_parts_amount)
    assert refund('method' => 'check', 'check_number' => '1042').valid?
  end

  def invoice_refund(attrs = {})
    RedmineQboBilling::InvoiceRefundForm.from_params(
      { 'customer_id' => '9101', 'invoice_id' => '601', 'txn_date' => '2026-11-20', 'method' => 'card',
        'reason' => 'Returned part', 'lines' => { '3' => { 'refund' => '1', 'quantity' => '2', 'amount' => '$1,060.00' },
                                                  '4' => { 'refund' => '0', 'quantity' => '', 'amount' => '' } } }.merge(attrs)
    )
  end

  def test_invoice_refund_form_lines
    form = invoice_refund('charge_fee' => '1')
    assert form.valid?, form.errors.full_messages.inspect
    assert_equal ['3'], form.chosen.keys
    assert_equal BigDecimal('2'), form.line(3).quantity_value
    assert_equal BigDecimal('1060'), form.line('3').amount_value
    assert_nil form.line('4').quantity_value
    assert_nil form.line('4').amount_value
    assert_nil form.line('9')
    assert form.charge_fee?
    assert_not form.note_issues?
    assert_includes RedmineQboBilling::InvoiceRefundForm.permitted, { lines: {} }
  end

  def test_invoice_refund_form_validation
    form = RedmineQboBilling::InvoiceRefundForm.from_params('method' => 'check')
    assert_not form.valid?
    %i[error_estimate_needs_customer error_refund_no_invoice error_refund_check_number error_refund_reason
       error_refund_no_lines].each { |key| assert_includes form.errors[:base], I18n.t(key) }
    assert_includes form.errors[:base], I18n.t(:error_estimate_field_invalid, field: I18n.t(:label_refund_date))
    assert_equal({}, form.lines)
  end
end
