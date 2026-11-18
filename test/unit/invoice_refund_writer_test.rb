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

class InvoiceRefundWriterTest < ActiveSupport::TestCase
  include QboRefundTestHelper
  Writer = RedmineQboBilling::InvoiceRefundWriter

  def setup
    User.current = User.find(1)
    @customer = create_customer
    Customer.any_instance.stubs(:email).returns('jane@example.com')
    RedmineQboBilling::RefundWriter.stubs(:fee_item).returns(fee_item)
    RedmineQboBilling::LaborItems.stubs(:ids).returns([])
    @gateway = FakeGateway.new
    @gateway.invoices << paid_invoice
  end

  def refund(form = invoice_refund_form, gateway: @gateway)
    Writer.refund!(form, user: User.find(1), gateway: gateway, mailer: FakeMailer)
  end

  def receipt
    @gateway.receipts.last
  end

  def test_lines
    lines = Writer.lines(paid_invoice, refunds: [])
    assert_equal %w[1 2 3], lines.map(&:key)
    assert_equal [false, true, true], lines.map(&:parts)
    assert_equal [false, true, true], lines.map(&:taxable)
    assert_equal BigDecimal('120'), lines[1].amount
    assert_equal BigDecimal('4'), lines[1].quantity
    assert_equal 'Brake Pads · Ceramic pads', lines[1].label
  end

  def test_lines_inside_bundles
    invoice = paid_invoice
    bundle = Quickbooks::Model::InvoiceLineItem.new
    bundle.id = '7'
    bundle.amount = BigDecimal('150')
    bundle.group_line_detail!
    bundle.group_line_detail.line_items = [sales_line(nil, 1, 'Labor', 1, 100, taxable: false), sales_line(nil, 5, 'Shim Kit', 1, 50)]
    invoice.line_items = invoice.line_items + [bundle]
    lines = Writer.lines(invoice, refunds: [])
    assert_equal %w[1 2 3 7.1 7.2], lines.map(&:key)
    assert_equal [false, true], lines.last(2).map(&:parts)
  end

  def test_paid_in_full_only
    assert Writer.paid_in_full?(paid_invoice)
    assert_not Writer.paid_in_full?(paid_invoice(balance: 10))
  end

  # Returned parts by check: $200.00 of parts, a $60.00 fee (30%), $14.00 tax back: $154.00
  def test_refund_parts_with_fee
    record = refund
    assert record.done?, record.message
    assert record.invoice?
    assert_equal '1234', record.invoice_number
    assert_equal BigDecimal('200'), record.lines_amount
    assert_equal BigDecimal('200'), record.parts_amount
    assert_equal BigDecimal('60'), record.fee_amount
    assert_equal BigDecimal('14'), record.tax_amount
    assert_equal BigDecimal('154'), record.refund_amount
    assert_equal BigDecimal('454'), record.credit_amount
    assert_equal '900', record.purchase_id
    assert_equal '3000', record.receipt_number
    assert_equal %w[2 3], record.refunded_lines.map(&:key)

    assert_equal '35', receipt.deposit_to_account_ref.value
    assert_equal '2', receipt.payment_method_ref.value
    assert_equal '5002', receipt.payment_ref_number
    assert_equal CUSTOMER_ID.to_s, receipt.customer_ref.value
    pads, rotor, fee = receipt.line_items
    assert_equal '3', pads.sales_item_line_detail.item_ref.value
    assert_equal BigDecimal('4'), pads.sales_item_line_detail.quantity
    assert_equal BigDecimal('30'), pads.sales_item_line_detail.unit_price
    assert_equal 'TAX', pads.sales_item_line_detail.tax_code_ref.value
    assert_equal BigDecimal('80'), rotor.amount
    assert_equal BigDecimal('-60'), fee.amount
    assert_equal '55', fee.sales_item_line_detail.item_ref.value
    assert_equal 'NON', fee.sales_item_line_detail.tax_code_ref.value
    assert_equal 'Restocking fee: 30% × $200.00 parts on Invoice #1234 = $60.00', fee.description
    assert_equal [[record.id, 'jane@example.com']], FakeMailer.sent
  end

  def test_fee_is_optional
    record = refund(invoice_refund_form(charge_fee: '0'))
    assert record.done?, record.message
    assert_equal BigDecimal('0'), record.fee_amount
    assert_equal BigDecimal('214'), record.refund_amount
    assert_equal 2, receipt.line_items.size
  end

  # Work with no parts: no fee, even when it's ticked, and no fee product/service needed
  def test_labor_only_has_no_fee
    RedmineQboBilling::RefundWriter.stubs(:fee_item).returns(nil)
    record = refund(invoice_refund_form(lines: { '1' => { refund: '1', quantity: '2' } }, method: 'card', check_number: ''))
    assert record.done?, record.message
    assert_equal BigDecimal('0'), record.parts_amount
    assert_equal BigDecimal('0'), record.fee_amount
    assert_equal BigDecimal('240'), record.refund_amount
    assert_equal 1, receipt.line_items.size
    assert_equal 'NON', receipt.line_items.first.sales_item_line_detail.tax_code_ref.value
    assert_equal '3', receipt.payment_method_ref.value
    assert_nil receipt.payment_ref_number
    assert_nil record.check_number
  end

  # A goodwill refund of part of the labor: an amount alone, no quantity or rate
  def test_partial_amount
    record = refund(invoice_refund_form(lines: { '1' => { refund: '1', quantity: '2', amount: '100' } }))
    assert record.done?, record.message
    detail = receipt.line_items.first.sales_item_line_detail
    assert_equal BigDecimal('100'), receipt.line_items.first.amount
    assert_nil detail.quantity
    assert_nil detail.unit_price
    assert_equal '1', detail.item_ref.value
    # It doesn't use up the 2 hours: what's left is $140.00, offered without a quantity
    assert_nil record.refunded_lines.first.quantity
    labor = Writer.lines(paid_invoice).first
    assert_equal BigDecimal('2'), labor.remaining_quantity
    assert_equal BigDecimal('140'), labor.remaining_amount
    assert_nil Writer.default_quantity(labor)
    assert_equal BigDecimal('4'), Writer.default_quantity(Writer.lines(paid_invoice)[1])
  end

  def test_a_line_isnt_refunded_twice
    first = refund(invoice_refund_form(lines: { '2' => { refund: '1', quantity: '2' } }))
    assert first.done?, first.message
    assert_equal BigDecimal('60'), first.lines_amount
    assert_equal BigDecimal('2'), receipt.line_items.first.sales_item_line_detail.quantity

    lines = Writer.lines(paid_invoice)
    assert_equal BigDecimal('2'), lines[1].remaining_quantity
    assert_equal BigDecimal('60'), lines[1].remaining_amount

    error = assert_raises(Writer::Error) { refund(invoice_refund_form(lines: { '2' => { refund: '1', quantity: '3' } })) }
    assert_match(/no more than 2/, error.message)
    error = assert_raises(Writer::Error) { refund(invoice_refund_form(lines: { '2' => { refund: '1', amount: '61' } })) }
    assert_match(/\$60\.00 is left/, error.message)
    assert refund(invoice_refund_form(lines: { '2' => { refund: '1', quantity: '2' } })).done?
  end

  def test_discount_share
    @gateway.invoices.replace([paid_invoice(discount: 44)])
    record = refund(invoice_refund_form(charge_fee: '0'))
    assert record.done?, record.message
    # 10% off the invoice: $20.00 of the $200.00 refunded
    assert_equal BigDecimal('20'), record.discount_amount
    discount = receipt.line_items.detect { |l| l.detail_type.to_s == 'DiscountLineDetail' }
    assert_equal BigDecimal('20'), discount.amount
    assert receipt.apply_tax_after_discount?
    assert_equal BigDecimal('192.60'), record.refund_amount
  end

  def test_checks_before_making_anything
    @gateway.invoices.replace([paid_invoice(balance: 100)])
    assert_raises(Writer::Error) { refund }
    @gateway.invoices.replace([paid_invoice(customer_id: 1)])
    assert_raises(Writer::Error) { refund }
    @gateway.invoices.replace([paid_invoice])
    assert_raises(Writer::Error) { refund(invoice_refund_form(lines: { '9' => { refund: '1' } })) }
    RedmineQboBilling::RefundWriter.stubs(:fee_item).returns(nil)
    assert_raises(Writer::Error) { refund }
    assert_equal 0, QboRefund.count
    assert_empty @gateway.receipts
  end

  def test_records_when_quickbooks_fails
    @gateway.fail_on = :receipt
    record = refund
    assert_not record.done?
    assert_match(/refund receipt couldn't be recorded/i, record.message)
    assert_nil record.purchase_id
    assert_empty FakeMailer.sent
    # A refund that made nothing doesn't use up the lines
    assert_equal BigDecimal('120'), Writer.lines(paid_invoice)[1].remaining_amount
  end

  def test_notes_the_work_orders
    Invoice.where(id: 950).delete_all
    invoice = Invoice.new(id: 950, doc_number: '1234', txn_date: Date.new(2026, 11, 2), customer_id: CUSTOMER_ID,
                          total_amount: 454, balance: 0)
    invoice.save!(validate: false)
    invoice.issues << Issue.find(1)
    status = Issue.find(1).status_id
    record = refund
    assert record.done?, record.message
    assert_equal [1], record.noted_issue_ids
    issue = Issue.find(1)
    assert_equal status, issue.status_id
    assert_equal 'Refunded $154.00 on invoice #1234 by Company check: Parts returned unused', issue.journals.last.notes
  ensure
    Invoice.where(id: 950).delete_all
  end

  def test_the_email
    record = refund
    message = QboRefundMailer.refund_summary(record, 'jane@example.com')
    body = message.body.to_s
    assert_includes body, "We've processed the refund for Invoice #1234."
    assert_includes body, 'Brake Pads · Ceramic pads: $120.00'
    assert_includes body, 'Lines refunded: $200.00'
    assert_includes body, 'Sales tax: $14.00'
    assert_includes body, 'Restocking fee (30% of parts): $60.00'
    assert_includes body, 'Refund: $154.00'
    assert_includes body, 'returned parts carry a restocking fee'
    assert_not_includes body, "Labor that wasn't done"
  end

  def test_the_pdf
    record = refund
    document = RedmineQboBilling::RefundPdf.new(record)
    assert document.render.start_with?('%PDF')
  end
end
