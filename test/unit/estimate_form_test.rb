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

class EstimateFormTest < ActiveSupport::TestCase
  Form = RedmineQboBilling::EstimateForm
  Line = Form::Line

  def line(attrs = {})
    Line.from_params(attrs)
  end

  def valid_form(attrs = {})
    Form.new({ customer_id: '9101', txn_date: '2026-11-20',
               lines: [line(item_id: '1', item_name: 'Labor', quantity: '2', rate: '120')] }.merge(attrs))
  end

  # Line

  def test_line_from_params_cleans_up_the_row
    row = line('id' => '', 'kind' => 'other', 'item_id' => '5', 'item_name' => ' Labor ', 'description' => ' Brakes ',
               'quantity' => ' 2 ', 'rate' => '$1,200.50', 'taxable' => '1', 'time_activity_id' => '')
    assert_nil row.id
    assert_nil row.kind
    assert_equal 'Labor', row.item_name
    assert_equal 'Brakes', row.description
    assert_equal BigDecimal('1200.50'), row.rate_value
    assert row.taxable?
    assert_nil row.time_activity_id
    assert_not line('taxable' => '0').taxable?
  end

  def test_line_amount_defaults_quantity_to_one_and_rounds
    assert_equal BigDecimal('45.50'), line(rate: '45.50').amount
    assert_equal BigDecimal('3.33'), line(quantity: '0.333', rate: '10').amount
    assert_equal BigDecimal('0'), line(description: 'note').amount
    assert_equal BigDecimal('0'), line(kind: 'subtotal', rate: '10').amount
  end

  def test_line_kinds
    assert line(kind: 'subtotal').subtotal?
    assert line(item_id: '1').item?
    assert_not line(kind: 'subtotal', item_id: '1').item?
    assert line(description: 'Notes').description_only?
    assert_not line(description: 'Notes', rate: '5').description_only?
    assert line.blank?
    assert_not line(kind: 'subtotal').blank?
    assert line(item_name: 'Typed only').unmatched_item?
    assert_not line(item_id: '1', item_name: 'Labor').unmatched_item?
  end

  def test_line_number_invalid
    assert line(quantity: 'two').number_invalid?
    assert line(rate: 'abc').number_invalid?
    assert_not line(quantity: '2', rate: '1,000').number_invalid?
    assert_not line(kind: 'subtotal', rate: 'abc').number_invalid?
  end

  # Parsing helpers

  def test_decimal
    assert_equal BigDecimal('1234.5'), Form.decimal('$1,234.50')
    assert_nil Form.decimal('')
    assert_nil Form.decimal('abc')
  end

  def test_date
    assert_equal Date.new(2026, 11, 20), Form.date('2026-11-20')
    assert_equal Date.new(2026, 1, 2), Form.date(Date.new(2026, 1, 2))
    assert_nil Form.date('')
    assert_nil Form.date('11/20/2026')
  end

  def test_custom_field_hash_keeps_numeric_ids_only
    field = Struct.new(:id).new(3)
    assert_equal({ '2' => 'VIN1', '3' => 'x' }, Form.custom_field_hash(2 => ' VIN1 ', 'name' => 'no', field => 'x'))
    assert_equal({}, Form.custom_field_hash(nil))
    form = Form.new(custom_fields: { 2 => 'VIN1' })
    assert_equal 'VIN1', form.custom_field(2)
    assert_equal 'VIN1', form.custom_field(Struct.new(:id).new('2'))
    assert_equal '', form.custom_field(9)
  end

  def test_from_params
    form = Form.from_params({ 'customer_id' => ' 9101 ', 'txn_date' => '2026-11-20', 'sync_token' => '',
                              'total_tax' => '4.20', 'linked_estimate_ids' => ['5', '', '5', '6'],
                              'custom_fields' => { '2' => 'VIN' },
                              'lines' => { '0' => { 'item_id' => '1', 'rate' => '10' }, '1' => { 'description' => 'Note' } } },
                            id: '42', document: 'invoice')
    assert_equal '42', form.id
    assert form.persisted?
    assert form.invoice?
    assert_nil form.sync_token
    assert_equal '9101', form.customer_id
    assert_equal '4.20', form.total_tax
    assert_equal %w[5 6], form.linked_estimate_ids
    assert_equal({ '2' => 'VIN' }, form.custom_fields)
    assert_equal 2, form.lines.size
    assert_equal 'Note', form.lines.last.description
  end

  def test_defaults
    form = Form.new
    assert_equal 'estimate', form.document
    assert_not form.invoice?
    assert_not form.persisted?
    assert_equal [], form.lines
    assert_equal [], form.linked_estimate_ids
  end

  # Totals and discounts

  def test_subtotal_skips_blank_rows
    form = Form.new(lines: [line(quantity: '2', rate: '10', item_id: '1'), line, line(rate: '5.25', item_id: '2')])
    assert_equal 2, form.filled_lines.size
    assert_equal BigDecimal('25.25'), form.subtotal
  end

  def test_percent_discount
    form = valid_form(discount_value: '10%')
    assert form.percent_discount?
    assert form.discount?
    assert_equal BigDecimal('24'), form.discount_amount
  end

  def test_amount_discount_and_unknown_type
    assert_equal BigDecimal('15.56'), valid_form(discount_type: 'amount', discount_value: '15.555').discount_amount
    assert_equal 'percent', valid_form(discount_type: 'bogus').discount_type
    assert_not valid_form(discount_value: '0').discount?
    assert_equal BigDecimal('0'), valid_form.discount_amount
  end

  def test_fully_paid_and_sent
    assert Form.new(balance: '0').fully_paid?
    assert Form.new(balance: '-1').fully_paid?
    assert_not Form.new(balance: '10').fully_paid?
    assert_not Form.new.fully_paid?
    assert Form.new(email_status: 'EmailSent').sent?
    assert_not Form.new(email_status: 'NeedToSend').sent?
  end

  # Validation

  def test_valid_form
    assert valid_form.valid?, valid_form.errors.full_messages.inspect
  end

  def test_needs_customer_line_and_date
    form = Form.new(txn_date: '')
    assert_not form.valid?
    assert_includes form.errors[:base], I18n.t(:error_estimate_needs_customer)
    assert_includes form.errors[:base], I18n.t(:error_estimate_needs_a_line)
    assert_includes form.errors[:base], I18n.t(:error_estimate_field_invalid, field: I18n.t(:label_estimate_date))
  end

  def test_invoice_date_label
    form = valid_form(txn_date: 'nope', document: 'invoice')
    assert_not form.valid?
    assert_includes form.errors[:base], I18n.t(:error_estimate_field_invalid, field: I18n.t(:label_invoice_date))
  end

  def test_bad_expiration_and_due_dates
    form = valid_form(expiration_date: 'soon', due_date: '13/45/2026')
    assert_not form.valid?
    assert_includes form.errors[:base], I18n.t(:error_estimate_field_invalid, field: I18n.t(:label_expiration_date))
    assert_includes form.errors[:base], I18n.t(:error_estimate_field_invalid, field: I18n.t(:label_due_date))
  end

  def test_line_errors_are_numbered_by_filled_row
    form = valid_form(lines: [line, line(item_name: 'Ghost'), line(item_id: '1', rate: 'x')])
    assert_not form.valid?
    assert_includes form.errors[:base], I18n.t(:error_estimate_line_unmatched_item, line: 1, name: 'Ghost')
    assert_includes form.errors[:base], I18n.t(:error_estimate_line_number, line: 2)
  end

  # A row with an unreadable price and no product or description: kept, so it needs a description
  def test_description_line_needs_text
    form = valid_form
    form.lines << line(rate: 'abc')
    assert_not form.valid?
    assert_includes form.errors[:base], I18n.t(:error_estimate_line_description, line: 2)
  end

  def test_email_addresses
    assert valid_form(email: 'a@example.com, b@example.com').valid?
    form = valid_form(email: 'a@example.com, not-an-address')
    assert_not form.valid?
    assert_includes form.errors[:base], I18n.t(:error_estimate_field_invalid, field: I18n.t(:label_customer_email))
  end

  def test_discount_validation
    invalid = I18n.t(:error_estimate_field_invalid, field: I18n.t(:label_discount_from_quickbooks))
    assert_includes valid_form(discount_value: '101').tap(&:valid?).errors[:base], invalid
    assert_includes valid_form(discount_value: '-5').tap(&:valid?).errors[:base], invalid
    assert_includes valid_form(discount_value: 'ten').tap(&:valid?).errors[:base], invalid
    assert_includes valid_form(discount_type: 'amount', discount_value: '241').tap(&:valid?).errors[:base],
                    I18n.t(:error_discount_too_large)
    assert valid_form(discount_type: 'amount', discount_value: '240').valid?
    assert valid_form(discount_value: '100').valid?
  end

  def test_plugin_errors_block_the_save
    RedmineQboBilling::IssueValues.stubs(:plugin_errors).returns(['One vehicle per invoice'])
    form = valid_form
    assert_not form.valid?
    assert_includes form.errors[:base], 'One vehicle per invoice'
  end
end
