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

class CustomerTest < ActiveSupport::TestCase
  def setup
    Customer.where(id: [9201, 9202, 9203]).delete_all
  end

  def customer(id, name, phone: nil, mobile: nil)
    record = Customer.new(id: id, name: name, phone_number: phone, mobile_phone_number: mobile)
    record.skip_qbo_push = true
    record.save!
    record
  end

  def test_name_is_title_cased_locally_and_in_quickbooks
    record = Customer.new(id: 9201, name: '  jane DOE llc ')
    assert_equal 'Jane DOE Llc', record.name
    assert_equal 'Jane DOE Llc', record.details.display_name
  end

  def test_phone_numbers_keep_digits_only
    record = customer(9201, 'Jane', phone: '(401) 555-0101', mobile: '+1 401.555.0102')
    assert_equal '4015550101', record.phone_number
    assert_equal '14015550102', record.mobile_phone_number
  end

  def test_to_s_adds_the_last_four_digits
    assert_equal 'Jane - 0101', customer(9201, 'Jane', phone: '4015550101').to_s
    assert_equal 'Bob', customer(9202, 'Bob').to_s
  end

  def test_needs_a_name_and_a_unique_id
    assert_not Customer.new(id: 9201, name: '').tap { |c| c.skip_qbo_push = true }.valid?
    customer(9201, 'Jane')
    duplicate = Customer.new(id: 9201, name: 'Other')
    duplicate.skip_qbo_push = true
    assert_not duplicate.valid?
  end

  def test_search_by_name_or_phone
    customer(9201, 'Jane Customer', phone: '4015550101')
    customer(9202, 'Bob Builder', mobile: '4015550199')
    customer(9203, '100% Jeep')
    assert_equal [9201], Customer.search('jane').pluck(:id)
    assert_equal [9202], Customer.search('0199').pluck(:id)
    # LIKE wildcards are matched literally
    assert_equal [9203], Customer.search('100%').pluck(:id)
  end

  def test_redmine_search_needs_every_token
    customer(9201, 'Jane Customer', phone: '4015550101')
    customer(9202, 'Jane Other')
    assert_equal({ 9201 => 9201 }, Customer.search_result_ranks_and_ids(%w[jane 0101], User.find(1)))
    assert_equal({}, Customer.search_result_ranks_and_ids([], User.find(1)))
  end

  def test_quickbooks_details_setters
    record = Customer.new(id: 9201, name: 'Jane')
    record.primary_phone = '401-555-0101'
    record.mobile_phone = '401-555-0102'
    record.email = 'jane@example.com'
    record.notes = 'Prefers texts'
    assert_equal '401-555-0101', record.primary_phone
    assert_equal '401-555-0102', record.mobile_phone
    assert_equal 'jane@example.com', record.email
    assert_equal 'Prefers texts', record.details.notes
    assert_nil record.project
  end

  def test_saving_pushes_to_quickbooks_unless_skipped
    CustomerService.any_instance.expects(:push).once.returns(true)
    Customer.create!(id: 9201, name: 'Jane')
    CustomerService.any_instance.expects(:push).never
    customer(9202, 'Bob')
  end
end
