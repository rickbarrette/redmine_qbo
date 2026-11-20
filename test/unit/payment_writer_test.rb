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

class PaymentWriterTest < ActiveSupport::TestCase
  include QboFakeServiceHelper
  fixtures :users

  Writer = RedmineQboBilling::PaymentWriter
  Form = RedmineQboBilling::PaymentForm

  def setup
    @customer = local_customer
    @fake = install_fake_quickbooks
    stub_local_syncs
    Invoice.where(id: [601, 602, 603]).delete_all
    @fake.query_results = { 'FROM Invoice' => [open_invoice(603, '1236', '2026-11-12', 50),
                                               open_invoice(601, '1234', '2026-11-01', 100),
                                               open_invoice(602, '1235', '2026-11-01', 200),
                                               open_invoice(604, '1237', '2026-11-02', 0)] }
  end

  def open_invoice(id, number, date, balance)
    qbo_invoice(id: id, doc_number: number, txn_date: Date.parse(date), total: 300, balance: balance)
  end

  def form(attrs = {})
    Form.from_params({ 'customer_id' => '9101', 'txn_date' => '2026-11-20', 'payment_method_id' => '2',
                       'amount' => '250' }.merge(attrs))
  end

  def payment(id: 801, total: 250, applied: { '601' => 100, '602' => 150 }, others: [])
    doc = Quickbooks::Model::Payment.new
    doc.id = id.to_s
    doc.sync_token = 2
    doc.customer_ref = qbo_ref(9101, 'Jane Customer')
    doc.txn_date = Date.new(2026, 11, 15)
    doc.total = BigDecimal(total.to_s)
    doc.payment_method_ref = qbo_ref(2, 'Check')
    doc.payment_ref_number = '1042'
    lines = applied.map do |invoice_id, amount|
      Quickbooks::Model::Line.new.tap do |line|
        line.amount = BigDecimal(amount.to_s)
        line.invoice_id = invoice_id
      end
    end
    others.each do |type|
      lines << Quickbooks::Model::Line.new.tap do |line|
        line.amount = 5
        line.linked_transactions = [qbo_link(type, 9)]
      end
    end
    doc.line_items = lines
    @fake.add(doc)
  end

  def applied(doc)
    doc.line_items.map { |l| [l.linked_transactions.first.txn_id, l.amount] }
  end

  def test_new_form
    user = User.find(2)
    user.stubs(:today).returns(Date.new(2026, 11, 20))
    result = Writer.new_form(customer: @customer, user: user)
    assert_equal ['9101', 'Jane Customer', '2026-11-20'], [result.customer_id.to_s, result.customer_name, result.txn_date]
  end

  def test_open_invoices_oldest_first
    list = Writer.open_invoices(@customer)
    assert_equal %w[1234 1235 1236], list.map { |i| i[:doc_number] }
    assert_equal '100.0', list.first[:balance]
  end

  def test_allocate
    invoices = [{ id: 'a', balance: '100' }, { id: 'b', balance: '0' }, { id: 'c', balance: '200' }]
    result, left = Writer.allocate(BigDecimal('150'), invoices)
    assert_equal [['a', BigDecimal('100')], ['c', BigDecimal('50')]], result.map { |i, take| [i[:id], take] }
    assert_equal BigDecimal('0'), left
    assert_equal BigDecimal('100'), Writer.allocate(400, invoices).last
  end

  def test_save_applies_oldest_first
    saved = Writer.save(form)
    assert_equal [['601', BigDecimal('100')], ['602', BigDecimal('150')]], applied(saved)
    assert_equal BigDecimal('250'), saved.total
    assert_equal '2', saved.payment_method_ref.value
    assert_nil saved.payment_ref_number
    assert_nil saved.private_note
  end

  def test_save_to_ticked_invoices_with_credit_left_over
    saved = Writer.save(form('invoice_ids' => ['603'], 'amount' => '80', 'reference' => '1042', 'memo' => 'Deposit'))
    assert_equal [['603', BigDecimal('50')]], applied(saved)
    assert_equal '1042', saved.payment_ref_number
    assert_equal 'Deposit', saved.private_note
  end

  def test_deposit_stays_unapplied
    saved = Writer.save(form('deposit' => '1'))
    assert_empty saved.line_items
  end

  def test_save_needs_a_customer_and_an_answer
    assert_raises(Writer::Error) { Writer.save(form('customer_id' => '424242')) }
    @fake.define_singleton_method(:create) { |_doc| nil }
    error = assert_raises(Writer::Error) { Writer.save(form) }
    assert_equal I18n.t(:error_payment_not_saved), error.message
  end

  def test_load_form
    payment
    result = Writer.load_form(801)
    assert result.persisted?
    assert_equal %w[601 602], result.invoice_ids
    assert_equal '250.0', result.amount
    assert_equal '0', result.deposit
    assert_equal '1042', result.reference
    assert_nil result.locked
    assert_raises(Writer::Error) { Writer.load_form(999) }
  end

  def test_update_unchanged_keeps_amounts
    payment
    edited = Writer.load_form(801)
    edited.memo = 'Edited'
    saved = Writer.save(edited)
    assert_equal [['601', BigDecimal('100')], ['602', BigDecimal('150')]], applied(saved)
    assert_equal 'Edited', saved.private_note
  end

  def test_update_with_a_new_amount_spreads_it_again
    payment(applied: { '602' => 200 }, total: 200)
    edited = Writer.load_form(801)
    edited.amount = '120'
    edited.invoice_ids = []
    saved = Writer.save(edited)
    # What this payment paid on 602 counts as open again
    assert_equal [['601', BigDecimal('100')], ['602', BigDecimal('20')]], applied(saved)
  end

  def test_update_refusals
    payment
    stale = Writer.load_form(801)
    stale.sync_token = '1'
    assert_raises(Writer::Conflict) { Writer.save(stale) }

    payment(others: ['CreditMemo'])
    error = assert_raises(Writer::Error) { Writer.save(Writer.load_form(801)) }
    assert_equal I18n.t(:error_payment_not_editable, types: 'CreditMemo'), error.message

    assert_raises(Writer::Error) { Writer.save(form.tap { |f| f.id = '999' }) }
  end

  def test_payment_methods
    @fake.query_results = { 'PaymentMethod' => [
      Quickbooks::Model::PaymentMethod.new(id: 2, name: 'Check', active: true),
      Quickbooks::Model::PaymentMethod.new(id: 1, name: 'cash', active: true),
      Quickbooks::Model::PaymentMethod.new(id: 3, name: 'Old card', active: false)
    ] }
    assert_equal [%w[cash 1], %w[Check 2]], Writer.payment_methods
  end

  def test_payment_methods_survive_errors
    QboConnectionService.stubs(:with_qbo_service).raises(StandardError, 'down')
    assert_equal [], Writer.payment_methods
  end

  def test_customer_payments_and_totals
    old = payment(id: 801)
    old.txn_date = Date.new(2026, 10, 1)
    old.unapplied_amount = 0
    recent = payment(id: 802, total: 100, applied: {})
    recent.unapplied_amount = 100
    @fake.query_results = { 'FROM Payment' => [old, recent] }
    list = Writer.customer_payments(@customer)
    assert_equal %w[802 801], list.map(&:id)
    assert_equal({ received: BigDecimal('350'), unapplied: BigDecimal('100') }, Writer.payment_totals(list))
  end

  def test_payment_method_name
    doc = payment
    assert_equal 'Check', Writer.payment_method_name(doc)
    doc.payment_method_ref = qbo_ref(7)
    Writer.stubs(:payment_methods).returns([%w[Visa 7]])
    assert_equal 'Visa', Writer.payment_method_name(doc)
    doc.payment_method_ref = nil
    assert_equal '', Writer.payment_method_name(doc)
  end

  def test_pdf
    @fake.pdf_body = '%PDF-1.4'
    assert_equal '%PDF-1.4', Writer.pdf(801)
  end
end
