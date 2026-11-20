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

class CustomersControllerTest < Redmine::IntegrationTest
  include QboFakeServiceHelper
  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles, :issues, :trackers,
           :projects_trackers, :issue_statuses, :enabled_modules, :enumerations, :workflows, :journals,
           :journal_details

  def setup
    # The search keeps its rows in memory, keyed by customer count and newest change (to the second); tests
    # roll back, so two tests can make the same key with different customers
    CustomerSearchService.instance_variable_set(:@candidates, nil)
    Customer.where(id: [9101, 9102]).delete_all
    @customer = local_customer(9101, 'Jane Customer')
    @customer.update_columns(phone_number: '4015550101')
    local_customer(9102, 'Bob Builder')
    Issue.find(1).update_column(:customer_id, 9101)
    Issue.find(8).update_column(:customer_id, 9101)
    CustomerToken.delete_all
    @fake = install_fake_quickbooks
  end

  # Gives jsmith's Manager role the permissions and logs jsmith in (again, if someone was logged in)
  def grant(*permissions)
    permissions.each { |p| Role.find(1).add_permission!(p) }
    reset!
    log_user('jsmith', 'jsmith')
  end

  def test_pages_need_view_customers
    log_user('jsmith', 'jsmith')
    Role.find(1).remove_permission!(:view_customers)
    get '/customers'
    assert_response :forbidden
    get '/customers/9101'
    assert_response :forbidden
    get '/customers/autocomplete', params: { q: 'jane' }
    assert_response :forbidden
  end

  def test_index_lists_and_sorts
    grant(:view_customers)
    get '/customers', params: { sort: 'name' }
    assert_response :success
    assert_select 'a[href=?]', '/customers/9101'
    assert_select 'a[href=?]', '/customers/9102'
  end

  def test_a_single_search_match_opens_the_customer
    grant(:view_customers)
    get '/customers', params: { search: 'Jane Customer' }
    assert_redirected_to '/customers/9101'
  end

  def test_show_lists_open_and_closed_issues
    grant(:view_customers)
    get '/customers/9101'
    assert_response :success
    assert_select 'a[href=?]', '/issues/1'
    assert_select 'a[href=?]', '/issues/8'
    get '/customers/424242'
    assert_response :not_found
  end

  def test_autocomplete
    grant(:view_customers)
    get '/customers/autocomplete', params: { q: 'jane custmer' }
    assert_response :success
    assert_equal [9101], JSON.parse(response.body).map { |c| c['id'] }
    get '/customers/autocomplete', params: { phone: '0101' }
    assert_equal ['Jane Customer'], JSON.parse(response.body).map { |c| c['name'] }
  end

  def test_create_needs_add_customers
    grant(:view_customers)
    Role.find(1).remove_permission!(:add_customers)
    get '/customers/new'
    assert_response :forbidden
    post '/customers', params: { customer: { name: 'New Person' } }
    assert_response :forbidden
  end

  def test_create_pushes_to_quickbooks
    grant(:view_customers, :add_customers)
    post '/customers', params: { customer: { name: 'new person', phone_number: '(401) 555-0123', email: 'new@example.com' } }
    customer = Customer.find_by(name: 'New Person')
    assert customer, 'customer created'
    assert_redirected_to "/customers/#{customer.id}"
    assert_equal '4015550123', customer.phone_number
    assert_equal 'new@example.com', @fake.created.last.email_address.address
  end

  # Customers are created from the page only; JSON requests are refused
  def test_json_create_is_refused
    Role.find(1).add_permission!(:view_customers)
    Role.find(1).add_permission!(:add_customers)
    with_settings rest_api_enabled: '1' do
      post '/customers.json', params: { customer: { name: 'Json Person' } },
                              headers: { 'X-Redmine-API-Key' => User.find(2).api_key }
    end
    assert_includes [401, 403, 406], response.status
    assert_not Customer.exists?(name: 'Json Person')
  end

  def test_invalid_customer_shows_the_form_again
    grant(:view_customers, :add_customers)
    post '/customers', params: { customer: { name: '' } }
    assert_response :unprocessable_entity
    assert_select '#errorExplanation'
  end

  def test_quickbooks_error_on_create_is_shown
    grant(:view_customers, :add_customers)
    @fake.define_singleton_method(:create) { |_doc| raise Quickbooks::IntuitRequestException, 'Duplicate Name Exists' }
    post '/customers', params: { customer: { name: 'Jane Customer' } }
    assert_redirected_to '/customers/new'
    assert_match 'Duplicate Name Exists', flash[:error]
  end

  def test_update_needs_edit_customers
    grant(:view_customers)
    Role.find(1).remove_permission!(:edit_customers)
    patch '/customers/9101', params: { customer: { name: 'Changed' } }
    assert_response :forbidden

    grant(:edit_customers)
    get '/customers/9101/edit'
    assert_response :success
    patch '/customers/9101', params: { customer: { name: 'jane changed' } }
    assert_redirected_to '/customers/9101'
    assert_equal 'Jane Changed', @customer.reload.name
    assert_equal 'Jane Changed', @fake.updated.last.display_name
  end

  def test_sync_is_admin_only
    grant(:view_customers)
    get '/customers/sync'
    assert_response :forbidden
    reset!
    log_user('admin', 'admin')
    Customer.expects(:sync)
    get '/customers/sync'
    assert_response :redirect
  end

  # ---- share links ----

  def test_share_needs_the_permission_and_a_visible_issue
    grant(:view_customers)
    Role.find(1).remove_permission!(:share_issues_with_customers)
    get '/customers/share/1'
    assert_response :forbidden

    grant(:share_issues_with_customers)
    get '/customers/share/1'
    token = CustomerToken.find_by(issue_id: 1)
    assert_redirected_to "/customers/view/#{token.token}"
    Project.find(2).update_column(:is_public, false)
    Member.where(user_id: 2, project_id: 2).destroy_all
    hidden = Issue.find(4)
    assert_not hidden.visible?(User.find(2))
    get "/customers/share/#{hidden.id}"
    assert_response :not_found
    assert_not CustomerToken.exists?(issue_id: hidden.id)
  end

  def test_share_link_shows_the_issue_to_anyone
    token = CustomerToken.create!(issue_id: 1, expires_at: 1.week.from_now)
    with_settings login_required: '1' do
      get "/customers/view/#{token.token}"
    end
    assert_response :success
    assert_select 'h3, h2, div.subject', text: /#{Regexp.escape(Issue.find(1).subject)}/
  end

  def test_expired_or_unknown_share_links_are_refused
    expired = CustomerToken.create!(issue_id: 1, expires_at: 1.week.from_now)
    expired.update_column(:expires_at, 1.day.ago)
    get "/customers/view/#{expired.token}"
    assert_response :forbidden
    get '/customers/view/not-a-token'
    assert_response :forbidden
  end
end
