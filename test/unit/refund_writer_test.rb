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

class RefundWriterTest < ActiveSupport::TestCase
  include QboRefundTestHelper
  Writer = RedmineQboBilling::RefundWriter

  def setup
    User.current = User.find(1)
    @customer = create_customer
    Customer.any_instance.stubs(:email).returns('jane@example.com')
    Writer.stubs(:fee_item).returns(fee_item)
    @gateway = FakeGateway.new(payments: [deposit(50, 300), deposit(51, '307.99', date: Date.new(2026, 11, 5))], estimate: estimate)
  end

  def refund(form = refund_form, gateway: @gateway)
    Writer.refund!(form, user: User.find(1), gateway: gateway, mailer: FakeMailer)
  end

  def test_fee
    assert_equal BigDecimal('92.40'), Writer.fee(BigDecimal('307.99'), 30)
    assert_equal BigDecimal('0'), Writer.fee(0, 30)
  end

  def test_parts_amount_leaves_out_labor
    assert_equal BigDecimal('307.99'), Writer.parts_amount(estimate)
  end

  def test_parts_inside_bundles
    bundle = Quickbooks::Model::InvoiceLineItem.new
    bundle.amount = BigDecimal('500')
    bundle.group_line_detail!
    bundle.group_line_detail.line_items = [item_line(1, 'Labor', 380), item_line(3, 'Brake Pads', 120)]
    subtotal = Quickbooks::Model::InvoiceLineItem.new
    subtotal.amount = BigDecimal('9999')
    subtotal.detail_type = 'SubTotalLineDetail'
    subtotal.sub_total_line_detail = Quickbooks::Model::SubTotalLineDetail.new
    e = estimate
    e.line_items = e.line_items + [bundle, subtotal]
    assert_equal BigDecimal('427.99'), Writer.parts_amount(e)
  end

  def test_refund_by_check
    record = refund
    assert record.done?, record.message
    # $92.40 fee (30% of $307.99) out of $607.99 credit: $515.59 refunded
    assert_equal BigDecimal('92.40'), record.fee_amount
    assert_equal BigDecimal('607.99'), record.credit_amount
    assert_equal BigDecimal('515.59'), record.refund_amount

    invoice = @gateway.invoices.first
    line = invoice.line_items.first
    assert_equal 'Restocking fee: 30% × $307.99 parts on E1068 = $92.40', line.description
    assert_equal '55', line.sales_line_item_detail.item_ref.value
    assert_equal BigDecimal('0'), invoice.balance

    purchase = @gateway.purchases.first
    assert_equal 'Check', purchase.payment_type
    assert_equal '5001', purchase.doc_number
    assert_equal '35', purchase.account_ref.value
    assert_equal 'Customer', purchase.entity_ref.type
    assert_equal CUSTOMER_ID.to_s, purchase.entity_ref.value
    expense = purchase.line_items.first
    assert_equal 'Refund for deposit on E1068', expense.description
    assert_equal '84', expense.account_based_expense_line_detail.account_ref.value
    assert_equal BigDecimal('515.59'), expense.amount

    # Oldest deposit pays the fee first; what's left of both goes on the check
    assert_equal [['50', BigDecimal('92.40'), invoice.id, 'Invoice'],
                  ['50', BigDecimal('207.60'), purchase.id, 'Check'],
                  ['51', BigDecimal('307.99'), purchase.id, 'Check']], @gateway.applied
    assert @gateway.payments.all? { |p| p.unapplied_amount.zero? }
    assert_equal BigDecimal('0'), record.balance_after
    assert_equal ['598'], @gateway.rejected
    assert record.estimate_closed?
    assert_equal [[record.id, 'jane@example.com']], FakeMailer.sent
    assert_equal 'jane@example.com', record.emailed_to
  end

  def test_card_refund_is_an_expense
    record = refund(refund_form(method: 'card', check_number: ''))
    assert record.done?, record.message
    purchase = @gateway.purchases.first
    assert_equal 'Cash', purchase.payment_type
    assert_nil purchase.doc_number
    assert_equal 'Refund for deposit on E1068 (card refund on the terminal)', purchase.line_items.first.description
    assert_equal %w[Invoice Expense Expense], @gateway.applied.map(&:last)
    assert_nil record.check_number
  end

  def test_credit_quickbooks_already_applied_to_the_fee
    @gateway.auto_apply = true
    record = refund
    assert record.done?, record.message
    assert_equal BigDecimal('515.59'), record.refund_amount
    # The fee was paid once, by QuickBooks
    assert_equal 1, @gateway.applied.count { |a| a.last == 'Invoice' }
  end

  def test_no_fee_refunds_everything
    record = refund(refund_form(parts_amount: '0', estimate_id: ''))
    assert record.done?, record.message
    assert_empty @gateway.invoices
    assert_equal BigDecimal('607.99'), record.refund_amount
    assert_equal 'Refund of customer credit', @gateway.purchases.first.line_items.first.description
    assert_empty @gateway.rejected
  end

  def test_checks_before_making_anything
    assert_raises(Writer::Error) { refund(refund_form, gateway: FakeGateway.new(estimate: estimate)) }
    assert_raises(Writer::Error) { refund(refund_form(parts_amount: '5000')) }
    assert_raises(Writer::Error) { refund(refund_form, gateway: FakeGateway.new(payments: [deposit(50, 300)], estimate: estimate(customer_id: 1))) }
    Writer.stubs(:fee_item).returns(nil)
    assert_raises(Writer::Error) { refund }
    assert_equal 0, QboRefund.count
    assert_empty @gateway.invoices
  end

  def test_records_the_step_that_failed
    @gateway.fail_on = :purchase
    record = refund
    assert_not record.done?
    assert_match(/refund couldn't be recorded/i, record.message)
    assert_equal 1, @gateway.invoices.size
    assert record.fee_invoice_id.present?
    assert_nil record.purchase_id
    assert_empty FakeMailer.sent
    assert_empty @gateway.rejected
  end

  def test_cancels_the_work_orders
    issue = Issue.find(1)
    issue.update_columns(estimate_id: 598) if Issue.column_names.include?('estimate_id')
    canceled = IssueStatus.find(5) # Closed (fixtures)
    Writer.stubs(:canceled_status).returns(canceled)
    record = refund
    assert record.done?, record.message
    assert_includes record.canceled_issue_ids, 1
    issue.reload
    assert_equal canceled, issue.status
    assert_match(/Order canceled and refunded: Customer canceled the order/, issue.journals.last.notes)
  end

  def test_warnings_dont_undo_the_refund
    Customer.any_instance.stubs(:email).returns('')
    Writer.stubs(:canceled_status).returns(nil)
    record = refund
    assert record.done?
    assert_match(/no email/i, record.message)
    assert_match(/canceled status/i, record.message)
  end

  def test_the_email
    record = refund
    ActionMailer::Base.deliveries.clear
    message = QboRefundMailer.refund_summary(record, 'jane@example.com')
    message.deliver_now
    assert_equal ['jane@example.com'], message.to
    assert_match(/Your refund from .*: \$515\.59/, message.subject)
    body = message.body.to_s
    assert_includes body, 'Hello Jane Customer,'
    assert_includes body, "We've processed the refund for E1068."
    assert_includes body, 'Parts: $307.99'
    assert_includes body, 'Restocking fee (30% of parts): $92.40'
    assert_includes body, 'Refund: $515.59'
    assert_includes body, 'company check (no. 5001)'
  end
end
