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

# What the plugin adds to Redmine's own pages: the issue's customer, estimate and invoices, the issue form, the
# issue list's Customer column and filter, spent time's Billed column, the issue history, the user form's
# employee, the bill and share links, the issue PDF, and the activity page
class RedminePagesTest < Redmine::IntegrationTest
  include QboFakeServiceHelper
  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles, :issues, :trackers,
           :projects_trackers, :issue_statuses, :enabled_modules, :enumerations, :workflows, :journals,
           :journal_details, :time_entries, :queries

  def setup
    @customer = local_customer(9101, 'Jane Customer')
    local_customer(9102, 'Bob Builder')
    Estimate.where(id: 598).delete_all
    Invoice.where(id: 601).delete_all
    @estimate = Estimate.create!(id: 598, doc_number: '1068', customer_id: 9101)
    @invoice = Invoice.create!(id: 601, doc_number: '1234', customer_id: 9101, txn_date: Date.new(2026, 11, 12))
    @issue = Issue.find(1)
    @issue.update_columns(customer_id: 9101, estimate_id: 598)
    @issue.invoices = [@invoice]
    @fake = install_fake_quickbooks
    Role.find(1).remove_permission!(:view_customers, :bill_issues, :share_issues_with_customers, :write_estimates)
  end

  def login(*permissions)
    permissions.each { |p| Role.find(1).add_permission!(p) }
    reset!
    log_user('jsmith', 'jsmith')
  end

  # ---- issue page ----

  def test_issue_shows_customer_estimate_and_invoices
    login
    get '/issues/1'
    assert_response :success
    assert_select '.customer_id .value a[href=?]', '/customers/9101', text: 'Jane Customer'
    assert_select '.estimate_id .value a[href=?]', '/estimates/598', text: '1068'
    assert_select '.invoice_id .value a[href=?]', '/invoices/601', text: '1234'
  end

  def test_estimate_actions_need_write_estimates
    login
    get '/issues/1'
    assert_select '.qbo-estimate-edit-link', 0
    login(:write_estimates)
    get '/issues/1'
    assert_select 'a.qbo-estimate-edit-link[href=?]', '/qbo_estimates/598/edit'
  end

  def test_bill_and_share_links_follow_permissions
    login
    get '/issues/1'
    assert_select 'a[href=?]', '/bill/1', 0
    assert_select 'a[href=?]', '/customers/share/1', 0
    login(:bill_issues, :share_issues_with_customers)
    get '/issues/1'
    assert_select 'a[href=?][data-method=post]', '/bill/1'
    assert_select 'a[href=?]', '/customers/share/1'
  end

  def test_issue_form_has_the_customer_and_their_estimates
    login
    get '/issues/1/edit'
    assert_response :success
    assert_select 'input.customer-name[data-autocomplete-url=?]', '/customers/autocomplete'
    assert_select 'input#customer_id[type=hidden][value=?]', '9101'
    assert_select 'select[name=?] option[value=?][selected]', 'issue[estimate_id]', '598'
  end

  def test_setting_the_customer_on_an_issue
    login
    patch '/issues/2', params: { issue: { customer_id: '9102' } }
    assert_redirected_to '/issues/2'
    assert_equal 9102, Issue.find(2).customer_id
  end

  # ---- issue history ----

  def test_history_names_the_customer_and_estimate
    journal = Journal.create!(journalized: @issue, user: User.find(2), notes: '')
    JournalDetail.create!(journal: journal, property: 'attr', prop_key: 'customer_id', old_value: '9102', value: '9101')
    JournalDetail.create!(journal: journal, property: 'attr', prop_key: 'estimate_id', old_value: '777', value: '598')
    JournalDetail.create!(journal: journal, property: 'invoice', prop_key: '601', value: '1234')
    login
    get '/issues/1'
    assert_select '.journal ul.journal-details li', text: /Bob Builder.*Jane Customer/
    # An estimate that's gone shows its id
    assert_select '.journal ul.journal-details li', text: /777.*1068/
    assert_select '.journal ul.journal-details li a[href$=?]', '/invoices/601', text: '1234'
  end

  def test_invoice_history_without_the_invoice
    journal = Journal.create!(journalized: @issue, user: User.anonymous, notes: '')
    JournalDetail.create!(journal: journal, property: 'invoice', prop_key: '999', value: '9999')
    login
    get '/issues/1'
    assert_select '.journal ul.journal-details li i', text: '9999'
  end

  def test_subjects_are_title_cased
    @issue.update!(subject: 'install LED light bar on JL')
    assert_equal 'Install LED Light Bar On JL', @issue.reload.subject
  end

  # ---- closing an issue bills it ----

  def test_closing_a_billable_issue_queues_billing
    User.find(3).update_column(:employee_id, 31)
    @issue.update_columns(assigned_to_id: 3)
    BillIssueTimeJob.expects(:perform_later).with(1)
    @issue.reload.update!(status: IssueStatus.where(is_closed: true).first)
  end

  def test_closing_without_an_employee_does_not_bill
    User.find(3).update_column(:employee_id, nil)
    @issue.update_columns(assigned_to_id: 3)
    BillIssueTimeJob.expects(:perform_later).never
    @issue.reload.update!(status: IssueStatus.where(is_closed: true).first)
  end

  # ---- issue list ----

  def test_customer_column_links_for_view_customers
    login
    get '/projects/ecookbook/issues', params: { set_filter: 1, c: %w[subject customer] }
    assert_response :success
    assert_select 'td.customer', text: 'Jane Customer'
    assert_select 'td.customer a', 0
    login(:view_customers)
    get '/projects/ecookbook/issues', params: { set_filter: 1, c: %w[subject customer] }
    assert_select 'td.customer a[href=?]', '/customers/9101'
  end

  def test_customer_name_filter
    login
    get '/projects/ecookbook/issues', params: { set_filter: 1, f: ['customer_name'], op: { customer_name: '~' },
                                                v: { customer_name: ['jane'] }, c: %w[subject] }
    assert_response :success
    assert_select 'tr#issue-1'
    assert_select 'tr#issue-2', 0

    get '/projects/ecookbook/issues', params: { set_filter: 1, f: ['customer_name'], op: { customer_name: '!~' },
                                                v: { customer_name: ['jane'] }, c: %w[subject] }
    assert_select 'tr#issue-1', 0
  end

  def test_customer_name_filter_sql_is_escaped
    query = IssueQuery.new(name: '_')
    sql = query.sql_for_customer_name_field('customer_name', '~', ["x' OR 1=1 --"])
    assert_match "LIKE '%x'' OR 1=1 --%'", sql.gsub('\\\'', "''")
    assert_nil query.sql_for_customer_name_field('customer_name', '=', ['x'])
  end

  def test_billed_column_and_filter_on_spent_time
    TimeEntry.where(id: 1).update_all(billed: true)
    login
    get '/projects/ecookbook/time_entries', params: { set_filter: 1, f: ['billed'], op: { billed: '=' }, v: { billed: ['1'] },
                                                      c: %w[hours billed] }
    assert_response :success
    assert_select 'tr#time-entry-1'
    assert_select 'th', text: I18n.t(:field_billed)
  end

  # ---- users ----

  def test_user_form_picks_the_employee
    Employee.where(id: [31, 32]).delete_all
    Employee.create!(id: 31, name: 'Tech One')
    User.find(3).update_column(:employee_id, 31)
    reset!
    log_user('admin', 'admin')
    get '/users/3/edit'
    assert_select 'select[name=?] option[value="31"][selected]', 'user[employee_id]', text: 'Tech One'
    patch '/users/3', params: { user: { employee_id: '' } }
    assert_nil User.find(3).employee_id
  end

  # ---- issue PDF ----

  def test_issue_pdf_includes_the_estimate
    # A plain one-page PDF, like QuickBooks' (Redmine's own PDFs have optional content, which the merge refuses)
    estimate_pdf = CombinePDF.new.tap { |p| p << CombinePDF.create_page }.to_pdf
    PdfService.any_instance.expects(:fetch_pdf).with(doc_ids: [598]).returns([estimate_pdf, '1068'])
    login
    get '/issues/1.pdf'
    assert_response :success
    assert_equal 'application/pdf', response.media_type
    assert_operator CombinePDF.parse(response.body).pages.size, :>=, 2
  end

  def test_issue_pdf_without_an_estimate
    @issue.update_column(:estimate_id, nil)
    PdfService.any_instance.expects(:fetch_pdf).never
    login
    get '/issues/1.pdf'
    assert_response :success
  end

  # ---- activity ----

  def test_activity_shows_quickbooks_documents_only_to_permitted_users
    login
    get '/activity'
    assert_select 'input[name=show_qbo_estimates]', 0
    login(:view_customers)
    get '/activity'
    assert_select 'input[name=show_qbo_estimates]'
    # Never on a project's activity
    get '/projects/ecookbook/activity'
    assert_select 'input[name=show_qbo_estimates]', 0
  end
end
