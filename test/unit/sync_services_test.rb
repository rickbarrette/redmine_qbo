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

# SyncServiceBase and the entity sync services: QuickBooks records cached locally
class SyncServicesTest < ActiveSupport::TestCase
  include QboFakeServiceHelper
  fixtures :projects, :users, :issues, :trackers, :issue_statuses, :enumerations

  def setup
    Customer.where(id: [9101, 9102]).delete_all
    Estimate.where(id: 598).delete_all
    Invoice.where(id: 601).delete_all
    Payment.where(id: 801).delete_all
    Employee.where(id: 31).delete_all
    Account.where(id: 84).delete_all
    QboSyncStatus.delete_all
    @fake = install_fake_quickbooks
  end

  def remote_customer(id, name, active: true, phone: nil)
    customer = Quickbooks::Model::Customer.new(id: id.to_s, display_name: name, active: active)
    if phone
      customer.primary_phone = Quickbooks::Model::TelephoneNumber.new
      customer.primary_phone.free_form_number = phone
    end
    customer
  end

  def test_customer_sync_by_id
    @fake.add(remote_customer(9101, 'jane customer', phone: '(401) 555-0101'))
    CustomerSyncService.new.sync_by_id(9101)
    customer = Customer.find(9101)
    assert_equal ['Jane Customer', '4015550101'], [customer.name, customer.phone_number]
  end

  def test_inactive_customer_is_removed
    local_customer(9101)
    @fake.add(remote_customer(9101, 'Jane Customer', active: false))
    CustomerSyncService.new.sync_by_id(9101)
    assert_not Customer.exists?(9101)
  end

  def test_full_sync_in_pages_reports_progress
    QboSyncStatus.running('Customer')
    @fake.query_results = { 'Customer' => [remote_customer(9101, 'Jane'), remote_customer(9102, 'Bob')] }
    CustomerSyncService.new.sync(full_sync: true)
    assert_equal %w[Bob Jane], Customer.where(id: [9101, 9102]).order(:name).pluck(:name)
    assert_equal 'SELECT * FROM Customer ORDER BY Id', @fake.queries.last
    assert_equal 2, QboSyncStatus.find_by(entity: 'Customer').processed
  end

  def test_incremental_sync_asks_for_changes_since_the_last_update
    local_customer(9101)
    CustomerSyncService.new.sync
    assert_match(/WHERE MetaData.LastUpdatedTime > '\d{4}-\d\d-\d\dT/, @fake.queries.last)
  end

  def test_estimate_sync
    local_customer(9101)
    remote = qbo_estimate(doc_number: '1068', status: 'Pending', total: '368.40',
                          lines: [qbo_sales_line(1, 10, 'Labor', 2, 120)])
    remote.txn_tax_detail = Quickbooks::Model::TransactionTaxDetail.new(total_tax: BigDecimal('8.40'))
    @fake.add(remote)
    Setting.stubs(:plugin_redmine_qbo).returns({})
    EstimateSyncService.new.sync_by_id(598)
    estimate = Estimate.find(598)
    assert_equal ['1068', 'Pending', BigDecimal('368.40'), 2.0, BigDecimal('8.40'), 9101],
                 [estimate.doc_number, estimate.txn_status, estimate.total_amount, estimate.hours, estimate.tax_amount, estimate.customer_id]
  end

  def test_estimate_sync_by_doc_number
    local_customer(9101)
    @fake.add(qbo_estimate(doc_number: '1068'))
    EstimateSyncService.new.sync_by_doc_number('1068')
    assert Estimate.exists?(598)
  end

  def test_invoice_sync_attaches_issues
    local_customer(9101)
    Issue.find(1).update_columns(customer_id: 9101)
    remote = qbo_invoice(doc_number: '1234', total: 100, balance: 100,
                         lines: [qbo_sales_line(1, 10, 'Labor', 1, 100, description: 'Install #1: lift')])
    @fake.add(remote)
    InvoiceSyncService.new.sync_by_id(601)
    invoice = Invoice.find(601)
    assert_equal ['1234', BigDecimal('100'), nil], [invoice.doc_number, invoice.balance, invoice.paid_on]
    assert_includes Issue.find(1).invoices, invoice
  end

  def test_unchanged_record_is_not_saved_again
    local_customer(9101, 'Jane Customer')
    @fake.add(remote_customer(9101, 'Jane Customer'))
    Customer.any_instance.expects(:save!).never
    CustomerSyncService.new.sync_by_id(9101)
  end

  def test_payment_waits_for_its_customer
    @fake.add(Quickbooks::Model::Payment.new(id: '801', total: BigDecimal('50'), unapplied_amount: BigDecimal('0'),
                                             txn_date: Date.new(2026, 11, 2), customer_ref: qbo_ref(424_242)))
    PaymentSyncService.new.sync_by_id(801)
    payment = Payment.find(801)
    assert_nil payment.customer_id
    assert_equal BigDecimal('50'), payment.total_amount
  end

  def test_employee_and_account_sync
    @fake.add(Quickbooks::Model::Employee.new(id: '31', display_name: 'Tech One', active: true))
    EmployeeSyncService.new.sync_by_id(31)
    assert_equal 'Tech One', Employee.find(31).name
    @fake.add(Quickbooks::Model::Account.new(id: '84', name: 'Sales', classification: 'Revenue', active: true))
    AccountSyncService.new.sync_by_id(84)
    assert_equal ['Sales', 'Revenue', true], Account.find(84).values_at(:name, :classification, :active)
  end

  def test_a_bad_record_is_logged_not_raised
    @fake.add(remote_customer(9101, ''))
    assert_nothing_raised { CustomerSyncService.new.sync_by_id(9101) }
    assert_not Customer.exists?(9101)
  end

  def test_a_record_inserted_meanwhile_is_updated
    local_customer(9101, 'Old Name')
    @fake.add(remote_customer(9101, 'New Name'))
    service = CustomerSyncService.new
    calls = 0
    Customer.stubs(:find_or_initialize_by).with { calls += 1 }.returns(Customer.new(id: 9101), Customer.find(9101))
    Customer.any_instance.stubs(:save!).raises(ActiveRecord::RecordNotUnique).then.returns(true)
    service.sync_by_id(9101)
    assert_equal 2, calls
  end
end
