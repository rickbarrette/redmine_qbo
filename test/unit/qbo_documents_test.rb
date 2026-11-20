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

# Estimate, Invoice and Payment: the local QuickBooks caches, and their events on the activity page (QboActivity)
class QboDocumentsTest < ActiveSupport::TestCase
  fixtures :users

  CUSTOMER_ID = 9301

  def setup
    Estimate.where(id: [9401, 9402]).delete_all
    Invoice.where(id: [9501, 9502, 9503]).delete_all
    Payment.where(id: [9601]).delete_all
    Customer.where(id: CUSTOMER_ID).delete_all
    customer = Customer.new(id: CUSTOMER_ID, name: 'Jane Customer')
    customer.skip_qbo_push = true
    customer.save!
  end

  def estimate(id, attrs = {})
    Estimate.create!({ id: id, doc_number: "E#{id}", customer_id: CUSTOMER_ID, txn_date: Date.new(2026, 11, 10),
                       total_amount: 1250, txn_status: 'Pending' }.merge(attrs))
  end

  def invoice(id, attrs = {})
    Invoice.create!({ id: id, doc_number: id.to_s, customer_id: CUSTOMER_ID, txn_date: Date.new(2026, 11, 10),
                      total_amount: 1250, balance: 1250, due_date: Date.new(2026, 12, 10) }.merge(attrs))
  end

  def user(*permissions)
    user = User.find(2)
    user.stubs(:allowed_to?).returns(false)
    permissions.each { |p| user.stubs(:allowed_to?).with(p, nil, global: true).returns(true) }
    user
  end

  def test_estimate
    record = estimate(9401)
    assert_equal 'E9401', record.to_s
    assert_equal 'E9401', record.name
    assert_not record.billed?
    RedmineQboBilling::EstimateWriter::BILLED_STATUSES.each do |status|
      assert estimate(9402, txn_status: status).billed?, status
      Estimate.where(id: 9402).delete_all
    end
    assert_not Estimate.new(id: 9402).valid?
  end

  def test_invoice_status_and_activity_description
    today = Date.new(2026, 11, 20)
    assert_equal :open, invoice(9501).status(today: today)
    partial = invoice(9502, balance: 400)
    assert_equal :partial, partial.status(today: today)
    User.current.stubs(:today).returns(today)
    assert_equal "$1,250.00 · #{I18n.t(:label_invoice_status_partial)} · #{I18n.t(:text_activity_invoice_owed, amount: '$400.00')}",
                 partial.activity_description
    assert_equal "$1,250.00 · #{I18n.t(:label_invoice_status_open)}", Invoice.find(9501).activity_description
    unknown = invoice(9503, balance: nil)
    assert_nil unknown.status
    assert_equal '$1,250.00', unknown.activity_description
    assert_equal '9503', unknown.to_s
  end

  def test_payment_activity_description
    payment = Payment.create!(id: 9601, customer_id: CUSTOMER_ID, txn_date: Date.new(2026, 11, 2),
                              total_amount: 500, unapplied_amount: 0)
    assert_equal '', payment.activity_description
    payment.unapplied_amount = 150
    assert_equal I18n.t(:text_activity_payment_unapplied, amount: '$150.00'), payment.activity_description
    assert_equal '2026-11-02 500.0', payment.to_s
  end

  def test_activity_needs_a_permission_and_no_project
    estimate(9401)
    assert_equal [], Estimate.find_events('qbo_estimates', user, nil, nil, {})
    viewer = user(:view_customers)
    assert_equal [9401], Estimate.find_events('qbo_estimates', viewer, nil, nil, {}).map(&:id)
    assert_equal [], Estimate.find_events('qbo_estimates', viewer, nil, nil, project: Project.new)
    assert_equal [], Estimate.find_events('qbo_estimates', viewer, nil, nil, author: viewer)
    assert_equal({ 'qbo_estimates' => { permission: :view_customers } }, Estimate.activity_provider_options)
    assert Payment.qbo_activity_visible_to?(user(:receive_payments))
  end

  def test_activity_by_quickbooks_date
    estimate(9401, txn_date: Date.new(2026, 11, 10))
    estimate(9402, txn_date: Date.new(2026, 11, 12))
    viewer = user(:write_estimates)
    found = Estimate.find_events('qbo_estimates', viewer, Date.new(2026, 11, 11), Date.new(2026, 11, 13), {})
    assert_equal [9402], found.map(&:id)
    assert_equal [9402], Estimate.find_events('qbo_estimates', viewer, nil, nil, limit: 1).map(&:id)
  end

  def test_activity_datetime
    record = estimate(9401, txn_date: Date.new(2026, 11, 10))
    assert_equal Time.local(2026, 11, 10, 12), record.activity_datetime
    record.txn_date = record.created_at.getlocal.to_date
    assert_equal record.created_at, record.activity_datetime
    assert_equal 'Jane Customer', record.activity_customer
    assert_nil record.project
    assert_nil record.activity_money(nil)
    assert_equal I18n.t(:label_none), Estimate.new.activity_customer
  end
end
