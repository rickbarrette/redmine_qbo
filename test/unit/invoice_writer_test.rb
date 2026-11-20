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

class InvoiceWriterTest < ActiveSupport::TestCase
  include QboFakeServiceHelper
  fixtures :projects, :users, :issues, :trackers, :issue_statuses, :enumerations

  Writer = RedmineQboBilling::InvoiceWriter
  Form = RedmineQboBilling::EstimateForm

  def setup
    @customer = local_customer
    @fake = install_fake_quickbooks
    stub_company
    stub_local_syncs
    Issue.where(estimate_id: [598, 599]).update_all(estimate_id: nil)
    Invoice.where(id: [601, 602]).delete_all
    @user = User.find(2)
    @user.stubs(:today).returns(Date.new(2026, 11, 20))
  end

  def estimate(**options)
    qbo_estimate(customer_name: 'Jane Customer', doc_number: '1068', status: 'Accepted',
                 custom_fields: [qbo_custom_field(1, 'Sales Rep', 'Ricky'), qbo_custom_field(2, 'VIN', '')],
                 lines: [qbo_sales_line(2, 10, 'Labor', 2, 120, taxable: false, description: 'Install #1: lift'),
                         qbo_sales_line(4, 11, 'Brake pads', 4, 30)], **options)
  end

  # Invoice #1234: $360 of lines plus $8.40 tax
  def invoice(total: '368.40', balance: '368.40', **options)
    doc = qbo_invoice(customer_name: 'Jane Customer', doc_number: '1234', total: total, balance: balance,
                      lines: [qbo_sales_line(1, 10, 'Labor', 2, 120, taxable: false), qbo_sales_line(2, 11, 'Brake pads', 4, 30)],
                      **options)
    doc.txn_tax_detail = Quickbooks::Model::TransactionTaxDetail.new
    doc.txn_tax_detail.total_tax = BigDecimal('8.40')
    doc
  end

  def form(attrs = {})
    Form.new({ document: 'invoice', customer_id: '9101', txn_date: '2026-11-20',
               lines: [Form::Line.new(item_id: '10', quantity: '2', rate: '120')] }.merge(attrs))
  end

  def allow(*permissions)
    @user.stubs(:allowed_to?).returns(false)
    permissions.each { |p| @user.stubs(:allowed_to?).with(p, nil, global: true).returns(true) }
  end

  # ---- new invoices ----

  def test_new_form
    result = Writer.new_form(customer: @customer, user: @user)
    assert result.invoice?
    assert_equal '2026-11-20', result.txn_date
    assert_equal 'Payment due on receipt', result.customer_memo
    assert_equal @user.name, result.sales_person
  end

  def test_from_estimate
    @fake.add(estimate(lines: [qbo_sales_line(2, 10, 'Labor', 2, 120), qbo_discount_line(24, percent: 10)]))
    Issue.find(1).update_column(:estimate_id, 598)
    RedmineQboBilling.expects(:field_defaults).with(@customer, issues: [Issue.find(1)]).returns('2' => 'VINFROMISSUE')
    result = Writer.from_estimate(598, user: @user)
    assert_equal '1068', result.converted_from
    assert_equal ['598'], result.linked_estimate_ids
    assert_equal 'Ricky', result.sales_person
    assert_equal({ '2' => 'VINFROMISSUE', '1' => 'Ricky' }, result.custom_fields)
    assert_equal '10', result.discount_value
    assert_equal [nil], result.lines.map(&:id)
  end

  def test_from_estimate_refuses_billed_estimates
    assert_raises(Writer::Error) { Writer.from_estimate(999, user: @user) }
    Invoice.create!(id: 601, doc_number: '1234', customer_id: 9101, txn_date: Date.new(2026, 11, 12))
    @fake.add(estimate(links: [qbo_link('Invoice', 601)]))
    error = assert_raises(Writer::Error) { Writer.from_estimate(598, user: @user) }
    assert_equal I18n.t(:error_estimate_already_invoiced, number: '1068', invoice: '1234'), error.message
  end

  def test_billing_error
    assert_nil Writer.billing_error(estimate)
    assert_equal I18n.t(:error_estimate_closed_billed, number: '1068', status: 'Closed'),
                 Writer.billing_error(estimate(status: 'Closed'))
    assert_equal I18n.t(:error_estimate_rejected, number: '1068'), Writer.billing_error(estimate(status: 'Rejected'))
    assert_equal I18n.t(:error_estimate_already_invoiced, number: '1068', invoice: '777'),
                 Writer.billing_error(estimate(links: [qbo_link('Invoice', 777)]))
  end

  # ---- reading ----

  def test_form_from_remote
    result = Writer.form_from_remote(invoice(balance: '100', links: [qbo_link('Estimate', 598), qbo_link('Payment', 9)]))
    assert result.invoice?
    assert_equal '1234', result.doc_number
    assert_equal ['598'], result.linked_estimate_ids
    assert_equal BigDecimal('268.40'), result.amount_paid
    assert_equal :paid, result.locked
    assert_nil Writer.form_from_remote(invoice).locked
  end

  def test_paid_helpers
    assert_not Writer.paid?(invoice)
    assert_not Writer.paid?(qbo_invoice)
    assert Writer.paid?(invoice(balance: '100'))
    assert_not Writer.fully_paid?(invoice(balance: '100'))
    assert Writer.fully_paid?(invoice(balance: '0'))
    assert_equal BigDecimal('0'), Writer.amount_paid(invoice)
  end

  def test_estimated_total_scales_the_tax
    remote = invoice
    assert_equal BigDecimal('368.40'), Writer.estimated_total(form(lines: [Form::Line.new(item_id: '1', rate: '360')]), remote)
    assert_equal BigDecimal('184.20'), Writer.estimated_total(form(lines: [Form::Line.new(item_id: '1', rate: '180')]), remote)
    remote.txn_tax_detail.total_tax = 0
    assert_equal BigDecimal('180'), Writer.estimated_total(form(lines: [Form::Line.new(item_id: '1', rate: '180')]), remote)
  end

  # ---- saving ----

  def test_create_closes_its_estimates_and_credits_their_sales_person
    @fake.add(estimate)
    Writer.save(form(linked_estimate_ids: ['598']), user: @user)
    created = @fake.created.first
    assert_equal({ 1 => 'Ricky' }, created.custom_fields.to_h { |f| [f.id, f.string_value] })
    assert_equal [%w[Estimate 598]], created.linked_transactions.map { |t| [t.txn_type, t.txn_id] }
    closed = @fake.updated.first
    assert_equal ['598', 'Closed'], [closed.id, closed.txn_status]
  end

  def test_create_refuses_an_estimate_billed_meanwhile
    @fake.add(estimate(status: 'Converted'))
    assert_raises(Writer::Error) { Writer.save(form(linked_estimate_ids: ['598']), user: @user) }
    assert_empty @fake.created
    assert_raises(Writer::Error) { Writer.save(form(linked_estimate_ids: ['999']), user: @user) }
  end

  def test_create_with_time_and_due_date
    Writer.save(form(due_date: '2026-12-20', lines: [Form::Line.new(item_id: '10', quantity: '1.5', rate: '120',
                                                                    time_activity_id: '77', description: 'Install #1: lift')]),
                user: @user)
    created = @fake.created.first
    assert_equal Date.new(2026, 12, 20), created.due_date
    assert_equal [%w[TimeActivity 77]], created.linked_transactions.map { |t| [t.txn_type, t.txn_id] }
    assert_equal '77', created.line_items.first.linked_transactions.first.txn_id
    assert_equal @user.name, created.custom_fields.first.string_value
  end

  def test_update_keeps_payment_links
    remote = @fake.add(invoice(links: [qbo_link('Estimate', 598), qbo_link('Payment', 9), qbo_link('TimeActivity', 5)]))
    @fake.add(estimate(status: 'Closed'))
    edited = Writer.form_from_remote(remote)
    Writer.save(edited, user: @user)
    update = @fake.updated.first
    assert_equal [%w[Estimate 598], %w[Payment 9]], update.linked_transactions.map { |t| [t.txn_type, t.txn_id] }
    # Already closed: left alone
    assert_equal 1, @fake.updated.size
  end

  def test_paid_invoice_needs_unlocking_and_permission
    remote = @fake.add(invoice(balance: '0'))
    edited = Writer.form_from_remote(remote)
    error = assert_raises(Writer::Error) { Writer.save(edited, user: @user) }
    assert_equal I18n.t(:error_invoice_paid), error.message

    allow(:write_invoices, :edit_partially_paid_invoices)
    error = assert_raises(Writer::Error) { Writer.save(edited, user: @user, unlock: true) }
    assert_equal I18n.t(:error_invoice_paid_not_allowed), error.message

    allow(:write_invoices, :edit_paid_invoices)
    Writer.save(edited, user: @user, unlock: true)
    assert_equal 1, @fake.updated.size
  end

  def test_unlocked_invoice_cannot_drop_below_what_was_paid
    allow(:write_invoices, :edit_paid_invoices)
    remote = @fake.add(invoice(balance: '0'))
    edited = Writer.form_from_remote(remote)
    edited.discount_type = 'amount'
    edited.discount_value = '50'
    error = assert_raises(Writer::Error) { Writer.save(edited, user: @user, unlock: true) }
    assert_match '$368.40', error.message
  end

  def test_update_refuses_stale_and_bundled_invoices
    remote = @fake.add(invoice)
    stale = Writer.form_from_remote(remote)
    stale.sync_token = '1'
    assert_raises(Writer::Conflict) { Writer.save(stale, user: @user) }
    bundle = Quickbooks::Model::InvoiceLineItem.new
    bundle.group_line_detail!
    remote.line_items = [bundle]
    assert_raises(Writer::Error) { Writer.save(Writer.form_from_remote(remote).tap { |f| f.lines = form.lines }, user: @user) }
    assert_raises(Writer::Error) { Writer.save(form(id: '999'), user: @user) }
    assert_raises(Writer::Error) { Writer.save(form(customer_id: '424242'), user: @user) }
  end

  def test_close_estimates_survives_errors
    @fake.add(estimate)
    @fake.define_singleton_method(:update) { |_doc, sparse: false| raise StandardError, 'down' }
    assert_nothing_raised { Writer.close_estimates(%w[598 598 999]) }
  end

  def test_send_email
    @fake.add(invoice)
    Writer.send_email(601, 'jane@example.com')
    assert_equal [%w[601 jane@example.com]], @fake.sent
    assert_raises(Writer::Error) { Writer.send_email(999, 'x@example.com') }
  end

  def test_estimate_sales_person
    @fake.add(estimate(id: 598, custom_fields: []))
    @fake.add(estimate(id: 599))
    assert_equal 'Ricky', Writer.estimate_sales_person(%w[598 599])
    assert_nil Writer.estimate_sales_person([])
    stub_company(custom_fields: [{ id: 2, name: 'VIN' }])
    assert_nil Writer.estimate_sales_person(%w[599])
  end

  def test_invoice_number
    assert_equal '601', Writer.invoice_number(601)
    Invoice.create!(id: 601, doc_number: '1234', customer_id: 9101, txn_date: Date.new(2026, 11, 12))
    assert_equal '1234', Writer.invoice_number('601')
  end

  # ---- importing ----

  def time_activity(id, hours: nil, minutes: nil, status: 'Billable', customer_id: 9101, start: nil, finish: nil)
    activity = Quickbooks::Model::TimeActivity.new
    activity.id = id.to_s
    activity.txn_date = '2026-11-18'
    activity.customer_ref = qbo_ref(customer_id)
    activity.employee_ref = qbo_ref(3, 'Tech One')
    activity.item_ref = qbo_ref(10, 'Labor')
    activity.hourly_rate = '120'
    activity.hours = hours
    activity.minutes = minutes
    activity.start_time = start
    activity.end_time = finish
    activity.billable_status = status
    activity.description = 'Install #1: lift kit'
    activity
  end

  def test_activity_hours
    assert_equal BigDecimal('1.5'), Writer.activity_hours(time_activity(1, hours: 1, minutes: 30))
    timed = time_activity(2, start: DateTime.new(2026, 11, 18, 8), finish: DateTime.new(2026, 11, 18, 10, 30))
    timed.break_minutes = 30
    assert_equal BigDecimal('2'), Writer.activity_hours(timed)
    assert_equal BigDecimal('0'), Writer.activity_hours(time_activity(3))
  end

  def test_import_options
    @fake.query_results = {
      'FROM TimeActivity' => [time_activity(71, hours: 2), time_activity(72, hours: 1, status: 'HasBeenBilled'),
                              time_activity(73, hours: 1, customer_id: 9999)],
      'FROM Estimate' => [estimate(id: 598, status: 'Pending'), estimate(id: 599, status: 'Closed')]
    }
    Issue.find(2).update_column(:estimate_id, 598)
    result = Writer.import_options(@customer, issue_ids: [3])
    assert_equal ['71'], result[:time_activities].map { |t| t[:id] }
    time = result[:time_activities].first
    assert_equal ['1', '2', '120', '240.0', 'Tech One', false], time.values_at(:issue_id, :quantity, :rate, :amount, :employee, :taxable)
    assert_equal ['598'], result[:estimates].map { |e| e[:id] }
    open = result[:estimates].first
    assert_equal '1', open[:issue_id]
    assert_match '#2:', open[:issue]
    assert_equal 2, open[:lines].size
    assert_kind_of Hash, result[:issue_values]
  end

  def test_time_falls_back_to_recent_time
    @fake.fail_query = /CustomerRef/
    @fake.query_results = { 'TxnDate >=' => [time_activity(71, hours: 2)] }
    assert_equal ['71'], Writer.open_time_activities(@customer).map { |t| t[:id] }
  end
end
