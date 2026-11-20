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

# Connecting to QuickBooks, manual syncs and billing, and Intuit's webhook
class QboControllerTest < Redmine::IntegrationTest
  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles, :issues, :trackers,
           :projects_trackers, :issue_statuses, :enabled_modules, :enumerations, :workflows

  SECRET = 'webhook-secret'.freeze

  def setup
    Qbo.delete_all
    Customer.where(id: 9101).delete_all
  end

  # Redmine keeps plugin settings with indifferent access (RedmineQbo.settings reads symbol keys)
  def settings(token)
    { 'webhook_token' => token }.with_indifferent_access
  end

  def signed(body, secret = SECRET)
    Base64.strict_encode64(OpenSSL::HMAC.digest(OpenSSL::Digest.new('sha256'), secret, body))
  end

  def post_webhook(body, signature)
    post '/qbo/webhook', params: body, headers: { 'CONTENT_TYPE' => 'application/json', 'intuit-signature' => signature }
  end

  # ---- webhook ----

  def test_webhook_with_a_valid_signature_queues_the_job
    body = '{"eventNotifications":[]}'
    WebhookProcessJob.expects(:perform_later).with(body)
    with_settings plugin_redmine_qbo: settings(SECRET) do
      post_webhook(body, signed(body))
    end
    assert_response :ok
  end

  def test_webhook_refuses_bad_or_missing_signatures
    body = '{"eventNotifications":[]}'
    WebhookProcessJob.expects(:perform_later).never
    with_settings plugin_redmine_qbo: settings(SECRET) do
      post_webhook(body, signed(body, 'wrong'))
      assert_response :unauthorized
      post_webhook(body, '')
      assert_response :unauthorized
    end
    with_settings plugin_redmine_qbo: settings('') do
      post_webhook(body, signed(body, ''))
      assert_response :unauthorized
    end
  end

  def test_webhook_needs_no_login
    body = '{}'
    WebhookProcessJob.stubs(:perform_later)
    with_settings login_required: '1', plugin_redmine_qbo: settings(SECRET) do
      post_webhook(body, signed(body))
    end
    assert_response :ok
  end

  # ---- admin pages ----

  def test_connecting_and_syncing_are_admin_only
    log_user('jsmith', 'jsmith')
    get '/qbo/authenticate'
    assert_response :forbidden
    get '/qbo/sync'
    assert_response :forbidden
    get '/qbo/oauth_callback', params: { code: 'x', state: 'y', realmId: '1' }
    assert_response :forbidden
  end

  def test_authenticate_redirects_to_intuit_with_a_state
    log_user('admin', 'admin')
    QboOauthService.expects(:authorization_url).with { |args| args[:state].present? && args[:callback_url].end_with?('/qbo/oauth_callback') }
                   .returns('https://appcenter.intuit.com/connect/oauth2?x=1')
    get '/qbo/authenticate'
    assert_redirected_to 'https://appcenter.intuit.com/connect/oauth2?x=1'
  end

  def test_oauth_callback_checks_the_state
    log_user('admin', 'admin')
    QboOauthService.expects(:exchange!).never
    get '/qbo/oauth_callback', params: { code: 'abc', state: 'forged', realmId: '123' }
    assert_redirected_to '/settings/plugin/redmine_qbo'
    assert_equal I18n.t(:notice_qbo_oauth_state_mismatch), flash[:error]
  end

  def test_oauth_callback_connects
    log_user('admin', 'admin')
    state = nil
    QboOauthService.stubs(:authorization_url).with { |args| state = args[:state] }.returns('https://intuit.example/')
    get '/qbo/authenticate'
    QboOauthService.expects(:exchange!).with(code: 'abc', callback_url: anything, realm_id: '123')
    get '/qbo/oauth_callback', params: { code: 'abc', state: state, realmId: '123' }
    assert_redirected_to '/qbo/sync'
    assert_equal I18n.t(:label_connected), flash[:notice]

    # The state is used once
    get '/qbo/oauth_callback', params: { code: 'abc', state: state, realmId: '123' }
    assert_equal I18n.t(:notice_qbo_oauth_state_mismatch), flash[:error]
  end

  def test_oauth_failure_is_reported
    log_user('admin', 'admin')
    state = nil
    QboOauthService.stubs(:authorization_url).with { |args| state = args[:state] }.returns('https://intuit.example/')
    get '/qbo/authenticate'
    QboOauthService.stubs(:exchange!).raises(OAuth2::Error.new(Struct.new(:parsed, :body, :status).new({}, 'bad', 400)))
    get '/qbo/oauth_callback', params: { code: 'abc', state: state, realmId: '123' }
    assert_redirected_to '/settings/plugin/redmine_qbo'
    assert_equal I18n.t(:label_error), flash[:error]
  end

  def test_sync
    log_user('admin', 'admin')
    QboSyncDispatcher.expects(:sync!).with(full_sync: true)
    get '/qbo/sync', params: { full_sync: 'true' }
    assert_response :redirect
    assert_equal I18n.t(:label_syncing), flash[:notice]
  end

  # ---- billing ----

  def billable_issue
    customer = Customer.new(id: 9101, name: 'Jane Customer')
    customer.skip_qbo_push = true
    customer.save!
    User.find(3).update_column(:employee_id, 31)
    Issue.find(1).tap { |i| i.update_columns(customer_id: 9101, assigned_to_id: 3) }
  end

  def test_bill_needs_the_permission
    billable_issue
    log_user('jsmith', 'jsmith')
    Role.find(1).remove_permission!(:bill_issues)
    post '/bill/1'
    assert_response :forbidden
    post '/bill/99999'
    assert_response :not_found
  end

  def test_bill_queues_the_job
    issue = billable_issue
    Qbo.new(realm_id: '1').save!(validate: false)
    Role.find(1).add_permission!(:bill_issues)
    log_user('jsmith', 'jsmith')
    BillIssueTimeJob.expects(:perform_later).with(issue.id)
    post "/bill/#{issue.id}"
    assert_redirected_to "/issues/#{issue.id}"
    assert_match 'Jane Customer', flash[:notice]
  end

  def test_bill_explains_what_is_missing
    Role.find(1).add_permission!(:bill_issues)
    log_user('jsmith', 'jsmith')
    BillIssueTimeJob.expects(:perform_later).never
    Issue.find(1).update_columns(customer_id: nil)
    post '/bill/1'
    assert_equal I18n.t(:notice_billing_error_no_customer), flash[:error]

    billable_issue
    post '/bill/1'
    assert_equal I18n.t(:notice_billing_error_no_qbo), flash[:error]

    User.find(3).update_column(:employee_id, nil)
    post '/bill/1'
    assert_equal I18n.t(:notice_billing_error_no_employee), flash[:error]
  end
end
