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

class QboRefundTest < ActiveSupport::TestCase
  def refund(attrs = {})
    QboRefund.new({ customer_id: 9101, method: 'card', status: 'done', kind: 'credit' }.merge(attrs))
  end

  def test_validations
    assert refund.valid?
    assert_not refund(method: 'cash').valid?
    assert_not refund(status: 'maybe').valid?
    assert_not refund(kind: 'other').valid?
    assert_not refund(customer_id: nil).valid?
  end

  def test_flags_and_method_name
    record = refund(method: 'check', kind: 'invoice', status: 'incomplete')
    assert record.check?
    assert record.invoice?
    assert_not record.done?
    assert_equal I18n.t(:label_refund_method_check), record.method_name
  end

  def test_issue_id_lists
    record = refund
    record.canceled_issue_ids = ['3', 3, 4]
    record.noted_issue_ids = [7]
    assert_equal [3, 4], record.canceled_issue_ids
    assert_equal [7], record.noted_issue_ids
    record[:canceled_issue_ids] = 'garbage'
    record[:noted_issue_ids] = nil
    assert_equal [], record.canceled_issue_ids
    assert_equal [], record.noted_issue_ids
  end

  def test_refunded_lines_round_trip
    record = refund
    record.refunded_lines = [QboRefund::RefundedLine.new(key: 3, description: 'Brake pads', quantity: 2,
                                                         amount: BigDecimal('60'), parts: true),
                             QboRefund::RefundedLine.new(key: 'L1', description: 'Labor', quantity: nil,
                                                         amount: 120, parts: nil)]
    lines = record.refunded_lines
    assert_equal %w[3 L1], lines.map(&:key)
    assert_equal '2', lines.first.quantity
    assert_equal BigDecimal('60'), lines.first.amount
    assert lines.first.parts
    assert_not lines.last.parts
    assert_nil lines.last.quantity
    record[:refunded_lines] = '{bad'
    assert_equal [], record.refunded_lines
  end

  def test_document_label
    assert_equal 'E1068', refund(estimate_number: '1068').document_label
    assert_nil refund.document_label
    assert_equal I18n.t(:label_refund_invoice_number, number: '1234'),
                 refund(kind: 'invoice', invoice_number: '1234').document_label
  end

  def test_purchase_url
    RedmineQbo.stubs(:sandbox_mode?).returns(false)
    assert_nil refund.purchase_url
    assert_equal 'https://app.qbo.intuit.com/app/expense?txnId=5', refund(purchase_id: '5').purchase_url
    assert_equal 'https://app.qbo.intuit.com/app/check?txnId=5', refund(purchase_id: '5', method: 'check').purchase_url
    assert_equal 'https://app.qbo.intuit.com/app/refundreceipt?txnId=5', refund(purchase_id: '5', kind: 'invoice').purchase_url
    RedmineQbo.stubs(:sandbox_mode?).returns(true)
    assert_equal 'https://sandbox.qbo.intuit.com/app/expense?txnId=5', refund(purchase_id: '5').purchase_url
  end

  def test_of_invoice_needs_a_receipt
    QboRefund.delete_all
    with_receipt = refund(kind: 'invoice', invoice_id: 601, purchase_id: '900').tap { |r| r.save!(validate: false) }
    refund(kind: 'invoice', invoice_id: 601, purchase_id: '').save!(validate: false)
    refund(kind: 'invoice', invoice_id: 602, purchase_id: '901').save!(validate: false)
    assert_equal [with_receipt.id], QboRefund.of_invoice(601).pluck(:id)
  end
end
