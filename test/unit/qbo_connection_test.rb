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

# The QuickBooks connection (Qbo), its OAuth token handling (QuickbooksOauth) and QboConnectionService
class QboConnectionTest < ActiveSupport::TestCase
  def setup
    Qbo.delete_all
  end

  def connection
    Qbo.create!(oauth2_access_token: 'access', oauth2_refresh_token: 'refresh', realm_id: '123')
  end

  def test_only_one_connection
    connection
    assert_not Qbo.new(realm_id: '456').valid?
  end

  def test_current_needs_a_connection
    assert_raises(RuntimeError) { QboConnectionService.current! }
    record = connection
    assert_equal record, QboConnectionService.current!
  end

  def test_with_qbo_service_needs_an_entity
    connection
    assert_raises(RuntimeError) { QboConnectionService.with_qbo_service { |_s| nil } }
  end

  def test_with_qbo_service_builds_the_service
    record = connection
    record.class.any_instance.stubs(:perform_authenticated_request).yields(record.oauth_access_token)
    service = nil
    QboConnectionService.with_qbo_service(entity: 'Invoice') { |s| service = s }
    assert_kind_of Quickbooks::Service::Invoice, service
    assert_equal '123', service.company_id
  end

  def test_last_sync_and_expiry_without_a_connection
    assert_equal I18n.t(:label_qbo_never_synced), Qbo.last_sync
    assert_nil Qbo.oauth2_access_token_expires_at
    assert_nil Qbo.oauth2_refresh_token_expires_at
  end

  def test_update_time_stamp
    record = connection
    Qbo.update_time_stamp
    assert_in_delta Time.now.to_i, record.reload.last_sync.to_i, 5
    assert_not_equal I18n.t(:label_qbo_never_synced), Qbo.last_sync
  end

  def test_authenticated_request_refreshes_and_retries
    record = connection
    record.expects(:refresh_token!).twice
    attempts = 0
    result = record.perform_authenticated_request do |token|
      attempts += 1
      raise Quickbooks::AuthorizationFailure if attempts < 3

      token.token
    end
    assert_equal 'access', result
  end

  def test_authenticated_request_gives_up
    record = connection
    record.stubs(:refresh_token!)
    error = assert_raises(RuntimeError) do
      record.perform_authenticated_request { |_token| raise Quickbooks::AuthorizationFailure }
    end
    assert_equal 'QuickbooksOauth:ExceededAuthAttempts', error.message
  end

  def test_refresh_token_saves_the_new_tokens
    record = connection
    refreshed = OAuth2::AccessToken.new(record.oauth_client, 'new-access', refresh_token: 'new-refresh',
                                        expires_at: 1.hour.from_now.to_i, 'x_refresh_token_expires_in' => 8_640_000)
    OAuth2::AccessToken.any_instance.stubs(:refresh!).returns(refreshed)
    record.refresh_token!
    record.reload
    assert_equal %w[new-access new-refresh], [record.oauth2_access_token, record.oauth2_refresh_token]
    assert_in_delta 100.days.from_now.to_i, record.oauth2_refresh_token_expires_at.to_i, 5
  end

  def test_oauth_client_follows_the_settings
    Setting.stubs(:plugin_redmine_qbo).returns({ 'oauth_consumer_key' => 'key', 'oauth_consumer_secret' => 'secret',
                                                 'sandbox' => '1' }.with_indifferent_access)
    client = Qbo.construct_oauth2_client
    assert_equal 'key', client.id
    assert Quickbooks.sandbox_mode
    url = QboOauthService.authorization_url(callback_url: 'https://redmine.example/qbo/oauth_callback', state: 'abc')
    assert_match 'state=abc', url
    assert_match 'scope=com.intuit.quickbooks.accounting', url
  ensure
    Quickbooks.sandbox_mode = false
  end

  def test_replace_swaps_the_connection
    connection
    Qbo.any_instance.stubs(:refresh_token!)
    replaced = QboConnectionService.replace!(token: 't', refresh_token: 'r', realm_id: '999')
    assert_equal [replaced.id], Qbo.pluck(:id)
    assert_equal '999', replaced.realm_id
  end
end
