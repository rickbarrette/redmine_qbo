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

class QboDraftTest < ActiveSupport::TestCase
  fixtures :users

  def setup
    QboDraft.delete_all
  end

  def draft(document, fields = {})
    QboDraft.create!(document: document, fields: fields)
  end

  def test_document_must_be_known
    assert_not QboDraft.new(document: 'payment').valid?
    assert QboDraft.new(document: 'invoice').valid?
  end

  def test_fields_round_trip_and_bad_data
    record = draft('estimate', 'customer_name' => 'Jane', 'lines' => { '0' => { 'rate' => '10', 'item_id' => '1' } })
    assert_equal 'Jane', record.reload.fields['customer_name']
    record.data = 'not json'
    assert_equal({}, record.fields)
    record.data = '[1, 2]'
    assert_equal({}, record.fields)
    record.data = nil
    assert_equal({}, record.fields)
  end

  def test_form_subtotal_and_line_count
    record = draft('invoice', 'lines' => { '0' => { 'item_id' => '1', 'quantity' => '2', 'rate' => '10' },
                                           '1' => { 'kind' => 'subtotal' }, '2' => { 'description' => 'Note' },
                                           '3' => {} })
    assert record.invoice?
    assert record.form.invoice?
    assert_equal BigDecimal('20'), record.subtotal
    assert_equal 2, record.line_count
  end

  def test_customer_name_falls_back_to_the_typed_name
    assert_equal 'Typed Name', draft('estimate', 'customer_name' => 'Typed Name').customer_name
    assert_nil draft('estimate').customer_name
  end

  def test_visible_by_permission
    estimate = draft('estimate')
    invoice = draft('invoice')
    user = User.find(2)
    user.stubs(:allowed_to?).returns(false)
    assert_empty QboDraft.visible(user)
    user.stubs(:allowed_to?).with(:write_estimates, nil, global: true).returns(true)
    assert_equal [estimate], QboDraft.visible(user).to_a
    user.stubs(:allowed_to?).with(:write_invoices, nil, global: true).returns(true)
    assert_equal [estimate, invoice], QboDraft.visible(user).order(:id).to_a
    assert_equal [invoice], QboDraft.for_document(:invoice).to_a
  end
end
