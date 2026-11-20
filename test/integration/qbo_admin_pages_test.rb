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

# Items, accounts and employee syncs (admin), and the business report
class QboAdminPagesTest < Redmine::IntegrationTest
  include QboFakeServiceHelper
  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles, :issues, :trackers,
           :projects_trackers, :issue_statuses, :enabled_modules, :enumerations, :workflows

  def setup
    Item.where(id: [9701, 9702]).delete_all
    Account.where(id: [9801, 9802]).delete_all
    @fake = install_fake_quickbooks
  end

  def item(id, name, attrs = {})
    Item.new({ id: id, name: name, description: '', unit_price: 10, active: true, type: 'Service' }.merge(attrs))
        .tap { |i| i.skip_qbo_push = true }.tap(&:save!)
  end

  def admin
    reset!
    log_user('admin', 'admin')
  end

  def jsmith
    reset!
    log_user('jsmith', 'jsmith')
  end

  def test_items_are_admin_only
    item(9701, 'Labor')
    jsmith
    %w[/items /items/new /items/9701 /items/9701/edit /items/sync /accounts /accounts/sync /employees/sync].each do |path|
      get path
      assert_response :forbidden, path
    end
    post '/items', params: { item: { name: 'Sneaky' } }
    assert_response :forbidden
  end

  def test_item_pages
    item(9701, 'Labor')
    admin
    get '/items'
    assert_response :success
    assert_select 'body', text: /Labor/
    get '/items/9701'
    assert_response :success
    get '/items/9701/edit'
    assert_response :success
    get '/items/424242'
    assert_response :not_found
  end

  def test_create_item_in_quickbooks
    admin
    post '/items', params: { item: { name: 'Brake Pads', description: 'Front pads', unit_price: '45', type: 'NonInventory', taxable: '1' } }
    created = @fake.created.last
    assert_equal 'Brake Pads', created.name
    assert_redirected_to "/items/#{created.id}"
    assert Item.exists?(created.id.to_i)
  end

  def test_duplicate_name_opens_the_existing_item
    admin
    @fake.define_singleton_method(:create) do |_doc|
      raise Quickbooks::IntuitRequestException, "Duplicate Name Exists Error:\nThe name supplied already exists. : Id=9702"
    end
    post '/items', params: { item: { name: 'Labor', description: '', unit_price: '1' } }
    assert_redirected_to '/items/9702'
  end

  def test_update_and_destroy_item
    item(9701, 'Labor')
    admin
    patch '/items/9701', params: { item: { name: 'Shop Labor', unit_price: '125' } }
    assert_redirected_to '/items/9701'
    assert_equal 'Shop Labor', Item.find(9701).name
    assert_equal 'Shop Labor', @fake.updated.last.name

    patch '/items/9701', params: { item: { unit_price: '-1' } }
    assert_response :unprocessable_entity

    delete '/items/9701'
    assert_redirected_to '/items'
    assert_not Item.exists?(9701)
    assert_equal false, @fake.updated.last.active?
  end

  def test_item_autocomplete_lists_sellable_items
    item(9701, 'Labor', description: 'Shop labor')
    item(9702, 'Labor old', active: false)
    admin
    get '/items/autocomplete', params: { q: 'lab' }
    assert_equal [9701], JSON.parse(response.body).map { |i| i['id'] }
  end

  def test_accounts
    Account.create!(id: 9801, name: 'Sales', classification: 'Revenue')
    Account.create!(id: 9802, name: 'Rent', classification: 'Expense')
    admin
    get '/accounts'
    assert_response :success
    assert_select 'body', text: /Sales/
    patch '/accounts/set_default', params: { default_account_id: 9801 }
    assert_redirected_to '/accounts'
    assert Account.find(9801).default
    patch '/accounts/set_default', params: { default_account_id: 424_242 }
    assert_equal I18n.t(:error_default_account_not_selected), flash[:error]
  end

  def test_admin_syncs
    admin
    Item.expects(:sync)
    Account.expects(:sync)
    Employee.expects(:sync)
    Payment.expects(:sync)
    %w[/items/sync /accounts/sync /employees/sync /qbo_payments/sync].each do |path|
      get path
      assert_response :redirect, path
    end
  end

  # ---- business report ----

  def test_report_needs_the_permission
    Role.find(1).remove_permission!(:view_business_reports)
    jsmith
    get '/qbo_reports'
    assert_response :forbidden
  end

  def test_report_remembers_projects
    Role.find(1).add_permission!(:view_business_reports)
    jsmith
    get '/qbo_reports', params: { period: 'last_month' }
    assert_response :success
    get '/qbo_reports', params: { project_ids: ['1', '999'], save_projects: '1' }
    assert_response :success
    assert_equal [1], User.find(2).pref[:qbo_report_project_ids]
    get '/qbo_reports'
    assert_response :success
  end
end
