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

class EstimateWriterTest < ActiveSupport::TestCase
  include QboFakeServiceHelper
  fixtures :projects, :users, :issues, :trackers, :issue_statuses, :enumerations

  Writer = RedmineQboBilling::EstimateWriter
  Form = RedmineQboBilling::EstimateForm

  def setup
    @customer = local_customer
    @fake = install_fake_quickbooks
    stub_company
    stub_local_syncs
    Setting.stubs(:plugin_redmine_qbo).returns('expiration_days' => '30')
    Issue.where(estimate_id: [598, 599]).update_all(estimate_id: nil)
    @user = User.find(2)
  end

  def remote_estimate(**options)
    qbo_estimate(customer_name: 'Jane Customer', doc_number: '1068', status: 'Pending',
                 custom_fields: [qbo_custom_field(1, 'Sales Rep', 'Ricky'), qbo_custom_field(2, 'VIN', '1C4HJXDG5JW123456')],
                 lines: [qbo_note_line(1, 'Lift kit install'),
                         qbo_sales_line(2, 10, 'Labor', 2, 120, taxable: false, description: 'Install'),
                         qbo_note_line(3, 'Subtotal: $240.00'),
                         qbo_sales_line(4, 11, 'Brake pads', 4, '30.5')],
                 **options)
  end

  def form(attrs = {})
    Form.new({ customer_id: @customer.id.to_s, txn_date: '2026-11-20', email: 'jane@example.com',
               lines: [Form::Line.new(item_id: '10', quantity: '2', rate: '120', taxable: false, description: 'Install'),
                       Form::Line.new(kind: 'subtotal'),
                       Form::Line.new(item_id: '11', quantity: '4', rate: '30.50', taxable: true)] }.merge(attrs))
  end

  # ---- reading ----

  def test_form_from_remote
    result = Writer.form_from_remote(remote_estimate)
    assert_equal '598', result.id
    assert_equal '3', result.sync_token
    assert_equal '9101', result.customer_id
    assert_equal 'Jane Customer', result.customer_name
    assert_equal '1068', result.doc_number
    assert_equal 'Ricky', result.sales_person
    assert_equal({ '1' => 'Ricky', '2' => '1C4HJXDG5JW123456' }, result.custom_fields)
    assert_equal [nil, nil, 'subtotal', nil], result.lines.map(&:kind)
    labor = result.lines[1]
    assert_equal %w[10 Labor 2 120], [labor.item_id, labor.item_name, labor.quantity, labor.rate]
    assert_not labor.taxable?
    assert result.lines[3].taxable?
    assert_equal '30.5', result.lines[3].rate
    assert_nil result.locked
  end

  def test_locked_states
    assert_equal :billed, Writer.form_from_remote(remote_estimate(status: 'Converted')).locked
    assert_equal :billed, Writer.form_from_remote(remote_estimate(links: [qbo_link('Invoice', 601)])).locked
    bundle = Quickbooks::Model::InvoiceLineItem.new
    bundle.group_line_detail!
    assert_equal :bundles, Writer.form_from_remote(remote_estimate(lines: [bundle])).locked
    Issue.find(1).update_column(:estimate_id, 598)
    assert_equal :linked, Writer.form_from_remote(remote_estimate).locked
  end

  def test_invoiced_on_lists_the_invoices
    Invoice.where(id: 601).delete_all
    Invoice.create!(id: 601, doc_number: '1234', customer_id: 9101, txn_date: Date.new(2026, 11, 12))
    result = Writer.form_from_remote(remote_estimate(links: [qbo_link('Invoice', 601), qbo_link('Invoice', 601), qbo_link('Payment', 7)]))
    assert_equal [%w[601 1234]], result.invoiced_on
  end

  def test_discount_fields
    percent = remote_estimate(lines: [qbo_sales_line(1, 10, 'Labor', 1, 100), qbo_discount_line(10, percent: 10)])
    assert_equal({ discount_type: 'percent', discount_value: '10' }, Writer.discount_fields(percent))
    amount = remote_estimate(lines: [qbo_discount_line('12.5'), qbo_discount_line('2.5', percent: 1)])
    assert_equal({ discount_type: 'amount', discount_value: '15' }, Writer.discount_fields(amount))
    assert_equal({}, Writer.discount_fields(remote_estimate))
    assert_equal BigDecimal('15'), Writer.discount_total(amount)
    assert_nil Writer.discount_total(remote_estimate)
  end

  def test_line_from_remote_skips_quickbooks_own_lines
    subtotal = Quickbooks::Model::InvoiceLineItem.new
    subtotal.detail_type = 'SubTotalLineDetail'
    assert_nil Writer.line_from_remote(subtotal)
    assert_nil Writer.line_from_remote(qbo_discount_line(5))
    assert Writer.line_from_remote(qbo_note_line(1, 'subtotal: -$1,000.25')).subtotal?
    assert_equal 'Subtotal for brakes', Writer.line_from_remote(qbo_note_line(1, 'Subtotal for brakes')).description
  end

  def test_custom_value
    remote = remote_estimate
    assert_equal 'Ricky', Writer.custom_value(remote, RedmineQboBilling::Company::Field.new(1, 'Sales Rep'))
    assert_equal '', Writer.custom_value(remote, RedmineQboBilling::Company::Field.new(3, 'Other'))
    # Unknown field: found by name, but never a hidden one
    assert_equal 'Ricky', Writer.custom_value(remote, nil, /sales/i)
    RedmineQboBilling::Company.stubs(:hidden_field_ids).returns([1])
    assert_equal '', Writer.custom_value(remote, nil, /sales/i)
  end

  def test_load
    @fake.add(remote_estimate)
    assert_equal '1068', Writer.load(598).doc_number
    error = assert_raises(Writer::Error) { Writer.load(999) }
    assert_equal I18n.t(:notice_estimate_not_found), error.message
  end

  # ---- new, duplicate, create for plugins ----

  def test_new_form
    @user.stubs(:today).returns(Date.new(2026, 11, 20))
    result = Writer.new_form(customer: @customer, user: @user)
    assert_equal '2026-11-20', result.txn_date
    assert_equal '2026-12-20', result.expiration_date
    assert_equal @user.name, result.sales_person
    assert_equal 'Thank you for your business', result.customer_memo
    assert_equal 2, result.lines.size
    assert result.lines.all?(&:taxable?)
    assert_equal 'Jane Customer', result.customer_name
  end

  def test_no_expiration_without_the_setting
    Setting.stubs(:plugin_redmine_qbo).returns({})
    assert_nil Writer.new_form(user: @user).expiration_date
  end

  def test_duplicate_form
    @fake.add(remote_estimate(lines: [qbo_sales_line(2, 10, 'Labor', 2, 120), qbo_discount_line(24, percent: 10)]))
    @user.stubs(:today).returns(Date.new(2026, 11, 20))
    copy = Writer.duplicate_form(598, user: @user)
    assert_not copy.persisted?
    assert_equal '1068', copy.duplicated_from
    assert_equal '2026-11-20', copy.txn_date
    assert_equal @user.name, copy.sales_person
    assert_equal 'percent', copy.discount_type
    assert_equal '10', copy.discount_value
    assert_equal [nil], copy.lines.map(&:id)
    assert_equal '1C4HJXDG5JW123456', copy.custom_field(2)
  end

  def test_create_estimate_for_another_plugin
    saved = Writer.create_estimate(customer: @customer, private_note: 'From #116',
                                   lines: [{ description: 'Added from: Install #116: lift' },
                                           { item_id: 11, quantity: 2.0, rate: '45.50', taxable: false }],
                                   custom_fields: { 2 => 'VIN9' }, txn_date: Date.new(2026, 11, 20))
    assert_equal 1, @fake.created.size
    assert_equal 'From #116', saved.private_note
    assert_equal 'Thank you for your business', saved.customer_memo
    sales = saved.line_items.find(&:sales_item?)
    assert_equal BigDecimal('91'), sales.amount
    assert_equal 'NON', sales.sales_line_item_detail.tax_code_ref.value
    assert_equal Date.new(2026, 12, 20), saved.expiration_date
    # Made without a user: no sales person
    assert_equal({ 2 => 'VIN9' }, saved.custom_fields.to_h { |f| [f.id, f.string_value] })
  end

  # ---- saving ----

  def test_create
    saved = Writer.save(form, user: @user)
    estimate = @fake.created.first
    assert_equal saved, estimate
    assert_equal 9101, estimate.customer_ref.value.to_i
    assert_equal 'jane@example.com', estimate.bill_email.address
    assert_equal Date.new(2026, 11, 20), estimate.txn_date
    assert_equal ['Install', 'Subtotal: $240.00', nil], estimate.line_items.map(&:description)
    assert_equal [1, 2, 3], estimate.line_items.map(&:line_num)
    assert_equal BigDecimal('122'), estimate.line_items.last.amount
    # Sales person on create
    assert_equal({ 1 => @user.name }, estimate.custom_fields.to_h { |f| [f.id, f.string_value] })
    assert_nil estimate.doc_number.to_s[/\A\d+\z/]
  end

  def test_create_numbers_estimates_with_custom_transaction_numbers
    stub_company(custom_txn_numbers: true)
    Estimate.where(id: [9401, 9402]).delete_all
    Estimate.create!(id: 9401, doc_number: '1068', customer_id: 9101)
    Estimate.create!(id: 9402, doc_number: 'X-1', customer_id: 9101)
    Writer.save(form, user: @user)
    assert_equal '1069', @fake.created.first.doc_number
  end

  def test_create_with_discount
    Writer.save(form(discount_value: '10'), user: @user)
    estimate = @fake.created.first
    discount = estimate.line_items.last
    assert discount.discount_item?
    assert_equal BigDecimal('36.2'), discount.amount
    assert_equal BigDecimal('10'), discount.discount_line_detail.discount_percent
    assert estimate.apply_tax_after_discount?
  end

  def test_needs_a_local_customer
    error = assert_raises(Writer::Error) { Writer.save(form(customer_id: '424242'), user: @user) }
    assert_equal I18n.t(:error_estimate_needs_customer), error.message
  end

  def test_update_keeps_line_ids_custom_fields_and_discount_account
    remote = @fake.add(remote_estimate(lines: [qbo_sales_line(2, 10, 'Labor', 2, 120), qbo_discount_line(5, account: '86')]))
    edited = Writer.form_from_remote(remote)
    edited.lines.first.quantity = '3'
    edited.lines << Form::Line.new(description: 'New note')
    edited.custom_fields['2'] = 'NEWVIN'
    edited.discount_type = 'amount'
    edited.discount_value = '20'
    Writer.save(edited, user: @user)

    update = @fake.updated.first
    assert_equal '598', update.id
    assert_equal ['2', nil, nil], update.line_items.map(&:id)
    assert_equal BigDecimal('360'), update.line_items.first.amount
    assert_equal '86', update.line_items.last.discount_line_detail.discount_account_ref.value
    fields = update.custom_fields.to_h { |f| [f.id, f.string_value] }
    # The sales person isn't replaced by whoever edits it
    assert_equal({ 1 => 'Ricky', 2 => 'NEWVIN' }, fields)
    assert_nil update.billing_address
  end

  def test_changing_customer_copies_the_billing_address
    other = local_customer(9102, 'Bob Builder')
    remote = @fake.add(remote_estimate)
    address = Quickbooks::Model::PhysicalAddress.new
    address.line1 = '1 Main St'
    @fake.customers['9102'] = Quickbooks::Model::Customer.new(billing_address: address)
    edited = Writer.form_from_remote(remote)
    edited.customer_id = other.id.to_s
    Writer.save(edited, user: @user)
    assert_equal '1 Main St', @fake.updated.first.billing_address.line1
  end

  def test_update_refuses_stale_billed_and_bundled_estimates
    remote = @fake.add(remote_estimate)
    stale = Writer.form_from_remote(remote)
    stale.sync_token = '2'
    assert_raises(Writer::Conflict) { Writer.save(stale, user: @user) }

    remote.txn_status = 'Closed'
    error = assert_raises(Writer::Error) { Writer.save(Writer.form_from_remote(remote), user: @user) }
    assert_equal I18n.t(:error_estimate_billed), error.message

    bundle = Quickbooks::Model::InvoiceLineItem.new
    bundle.group_line_detail!
    remote.txn_status = 'Pending'
    remote.line_items = [qbo_sales_line(2, 10, 'Labor', 1, 1), bundle]
    error = assert_raises(Writer::Error) { Writer.save(Writer.form_from_remote(remote).tap { |f| f.locked = nil }, user: @user) }
    assert_equal I18n.t(:error_estimate_has_bundles), error.message

    assert_raises(Writer::Error) { Writer.save(form.tap { |f| f.id = '999' }, user: @user) }
    assert_empty @fake.updated
  end

  def test_rate_falls_back_to_the_item_price
    Item.where(id: 11).delete_all
    item = Item.new(id: 11, name: 'Brake pads', description: '', unit_price: 42)
    item.skip_qbo_push = true
    item.save!
    Writer.save(form(lines: [Form::Line.new(item_id: '11', quantity: '2')]), user: @user)
    assert_equal BigDecimal('84'), @fake.created.first.line_items.first.amount
  end

  def test_unsaved_answer_is_an_error
    @fake.define_singleton_method(:create) { |_doc| nil }
    error = assert_raises(Writer::Error) { Writer.save(form, user: @user) }
    assert_equal I18n.t(:error_estimate_not_saved), error.message
  end

  # ---- accepting, emailing, custom fields ----

  def test_accept_a_pending_estimate
    @fake.add(remote_estimate)
    @user.stubs(:today).returns(Date.new(2026, 11, 20))
    result = Writer.accept(598, user: @user)
    assert result.accepted?
    update = @fake.updated.first
    assert_equal 'Accepted', update.txn_status
    assert_equal 'Jane Customer', update.accepted_by
    assert_equal Date.new(2026, 11, 20), update.accepted_date
    assert_equal 4, update.line_items.size
  end

  def test_accept_leaves_other_statuses_and_reports_failures
    @fake.add(remote_estimate(status: 'Rejected'))
    result = Writer.accept(598, user: @user)
    assert_equal :unchanged, result.outcome
    assert_equal 'Rejected', result.message
    assert_empty @fake.updated

    assert Writer.accept(999, user: @user).failed?

    @fake.add(remote_estimate)
    @fake.define_singleton_method(:update) { |_doc, sparse: false| raise Quickbooks::IntuitRequestException, 'Stale' }
    result = Writer.accept(598, user: @user)
    assert result.failed?
    assert_equal 'Stale', result.message
  end

  def test_send_email
    @fake.add(remote_estimate)
    assert_equal '598', Writer.send_email(598, 'jane@example.com').id
    assert_equal [%w[598 jane@example.com]], @fake.sent
    assert_raises(Writer::Error) { Writer.send_email(999, 'jane@example.com') }
  end

  def test_custom_field_value
    @fake.add(remote_estimate)
    assert_equal '1C4HJXDG5JW123456', Writer.custom_field_value(598, 2)
    assert_nil Writer.custom_field_value(598, 9)
    assert_nil Writer.custom_field_value('', 2)
    assert_nil Writer.custom_field_value(999, 2)
  end

  # ---- helpers ----

  def test_subtotal_text
    assert_equal 'Subtotal: $1,342.60', Writer.subtotal_text('1342.6')
    assert_equal 'Subtotal: -$5.00', Writer.subtotal_text(-5)
    assert_equal 'Subtotal: $1,000,000.00', Writer.subtotal_text(1_000_000)
  end

  def test_tidy_subtotals
    lines = [Form::Line.new(kind: 'subtotal'), Form::Line.new(rate: '1'), Form::Line.new(kind: 'subtotal'),
             Form::Line.new(kind: 'subtotal'), Form::Line.new(rate: '2')]
    assert_equal [nil, 'subtotal', nil], Writer.tidy_subtotals(lines).map(&:kind)
  end

  def test_subtotals_total_their_own_section
    Writer.save(form(lines: [Form::Line.new(item_id: '1', rate: '10'), Form::Line.new(description: 'Note'),
                             Form::Line.new(kind: 'subtotal'), Form::Line.new(item_id: '1', rate: '5'),
                             Form::Line.new(kind: 'subtotal')]), user: @user)
    assert_equal ['Subtotal: $10.00', 'Subtotal: $5.00'],
                 @fake.created.first.line_items.map(&:description).grep(/Subtotal/)
  end

  def test_plain_number_and_format_address
    assert_equal '2', Writer.plain_number(BigDecimal('2.0'))
    assert_equal '12.5', Writer.plain_number('12.50')
    assert_equal '', Writer.plain_number(nil)
    address = Quickbooks::Model::PhysicalAddress.new
    address.line1 = '1 Main St'
    address.line2 = ' '
    address.city = 'Providence'
    address.country_sub_division_code = 'RI'
    address.postal_code = '02903'
    assert_equal "1 Main St\nProvidence, RI 02903", Writer.format_address(address)
    assert_equal '', Writer.format_address(nil)
  end

  def test_time_activity_links
    line = Quickbooks::Model::InvoiceLineItem.new
    Writer.link_time_activity(line, '77')
    assert_equal '77', Writer.linked_time_activity_id(line)
    Writer.link_time_activity(line, '')
    assert_equal '77', Writer.linked_time_activity_id(line)
  end

  def test_next_doc_number
    Invoice.delete_all
    assert_nil Writer.next_doc_number(Invoice)
  end
end
