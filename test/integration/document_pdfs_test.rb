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

# Estimate and invoice PDFs: users with a billing permission open any of them; other logged-in users only the
# documents attached to issues they can see; share-link customers only their own issue's documents
class DocumentPdfsTest < Redmine::IntegrationTest
  include QboFakeServiceHelper
  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles, :issues, :trackers,
           :projects_trackers, :issue_statuses, :enabled_modules, :enumerations

  def setup
    local_customer
    Estimate.where(id: [598, 599]).delete_all
    Invoice.where(id: [601, 602]).delete_all
    Estimate.create!(id: 598, doc_number: '1068', customer_id: 9101)
    Estimate.create!(id: 599, doc_number: '1069', customer_id: 9101)
    @invoice = Invoice.create!(id: 601, doc_number: '1234', customer_id: 9101, txn_date: Date.new(2026, 11, 12))
    Invoice.create!(id: 602, doc_number: '1235', customer_id: 9101, txn_date: Date.new(2026, 11, 12))
    issue = Issue.find(1)
    issue.update_column(:estimate_id, 598)
    issue.invoices = [@invoice]
    CustomerToken.delete_all
    @token = CustomerToken.create!(issue_id: 1, expires_at: 1.week.from_now)
    @fake = install_fake_quickbooks
    [qbo_estimate(id: 598, doc_number: '1068'), qbo_estimate(id: 599, doc_number: '1069'),
     qbo_invoice(id: 601, doc_number: '1234'), qbo_invoice(id: 602, doc_number: '1235')].each { |d| @fake.add(d) }
    @fake.pdf_body = CombinePDF.new.tap { |pdf| pdf << CombinePDF.create_page }.to_pdf
    Role.find(1).remove_permission!(:view_customers, :write_estimates, :write_invoices, :view_payments,
                                    :receive_payments, :issue_refunds)
  end

  def login(*permissions)
    permissions.each { |p| Role.find(1).add_permission!(p) }
    reset!
    log_user('jsmith', 'jsmith')
  end

  def open_share_link
    get "/customers/view/#{@token.token}"
    assert_response :success
  end

  def test_billing_users_open_any_estimate
    %i[view_customers write_estimates].each do |permission|
      Role.find(1).remove_permission!(:view_customers, :write_estimates)
      login(permission)
      get '/estimates/599'
      assert_response :success, permission
      assert_equal 'application/pdf', response.media_type
      assert_match 'estimate 1069.pdf', response.headers['Content-Disposition']
      get '/estimates/doc', params: { search: '1069' }
      assert_response :success, permission
    end
  end

  def test_other_users_open_only_estimates_on_issues_they_can_see
    login
    get '/estimates/598'
    assert_response :success
    get '/estimates/doc', params: { search: '1068' }
    assert_response :success
    get '/estimates/599'
    assert_response :forbidden
    get '/estimates/doc', params: { search: '1069' }
    assert_response :forbidden
  end

  def test_estimate_on_a_hidden_issue_is_refused
    Issue.find(1).update_column(:estimate_id, nil)
    Issue.find(4).update_column(:estimate_id, 598)
    Project.find(2).update_column(:is_public, false)
    Member.where(user_id: 2, project_id: 2).destroy_all
    login
    get '/estimates/598'
    assert_response :forbidden
  end

  def test_only_billing_users_sync_missing_estimates
    login
    Estimate.expects(:sync_by_id).never
    get '/estimates/777'
    assert_response :forbidden

    login(:view_customers)
    Estimate.expects(:sync_by_id).with('777')
    get '/estimates/777'
    assert_response :redirect
    assert_equal I18n.t(:notice_estimate_not_found), flash[:error]
  end

  def test_billing_users_open_any_invoice
    %i[view_customers write_invoices view_payments receive_payments issue_refunds].each do |permission|
      Role.find(1).remove_permission!(:view_customers, :write_invoices, :view_payments, :receive_payments, :issue_refunds)
      login(permission)
      get '/invoices/602'
      assert_response :success, permission
      get '/invoices/601', params: { invoice_ids: %w[601 602] }
      assert_response :success, permission
    end
  end

  def test_other_users_open_only_invoices_on_issues_they_can_see
    login
    get '/invoices/601'
    assert_response :success
    assert_match 'invoice 1234.pdf', response.headers['Content-Disposition']
    get '/invoices/602'
    assert_response :forbidden
    get '/invoices/601', params: { invoice_ids: %w[601 602] }
    assert_response :forbidden
  end

  def test_estimate_search_shows_only_to_billing_users
    login
    get '/projects/ecookbook/issues'
    assert_select '#estimate-search-form', 0
    login(:write_estimates)
    get '/projects/ecookbook/issues'
    assert_select '#estimate-search-form'
  end

  def test_anonymous_visitors_must_log_in
    get '/estimates/598'
    assert_redirected_to %r{/login}
    get '/invoices/601'
    assert_redirected_to %r{/login}
  end

  def test_share_link_customer_sees_only_their_estimate
    open_share_link
    get '/estimates/598'
    assert_response :success
    get '/estimates/doc', params: { search: '1068' }
    assert_response :success
    get '/estimates/599'
    assert_response :forbidden
    get '/estimates/doc', params: { search: '1069' }
    assert_response :forbidden
  end

  def test_share_link_customer_sees_only_their_invoices
    open_share_link
    get '/invoices/601'
    assert_response :success
    assert_match 'invoice 1234.pdf', response.headers['Content-Disposition']
    get '/invoices/602'
    assert_response :forbidden
    get '/invoices/601', params: { invoice_ids: %w[601 602] }
    assert_response :forbidden
  end

  def test_expired_share_link_stops_working
    open_share_link
    @token.update_column(:expires_at, 1.minute.ago)
    get '/invoices/601'
    assert_redirected_to %r{/login}
  end

  def test_invoice_pdf_failure_redirects
    login(:write_invoices)
    get '/invoices/999'
    assert_response :redirect
    assert_equal I18n.t(:notice_invoice_not_found), flash[:error]
  end

  def test_syncs_are_admin_only
    login
    get '/estimates/sync'
    assert_response :forbidden
    get '/invoices/sync'
    assert_response :forbidden
    reset!
    log_user('admin', 'admin')
    Estimate.expects(:sync)
    Invoice.expects(:sync)
    get '/estimates/sync'
    get '/invoices/sync'
  end
end
