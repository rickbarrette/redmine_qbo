#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class QboController < ApplicationController
  include AuthHelper

  before_action :require_user, except: :webhook
  skip_before_action :verify_authenticity_token, :check_if_login_required, only: :webhook

  # Initiates the OAuth authentication process by redirecting the user to the QuickBooks authorization URL. The callback URL is generated based on the application's settings and routes.
  def authenticate
    redirect_to QboOauthService.authorization_url(callback_url: callback_url)
  end

  # Handles the OAuth callback from QuickBooks. Exchanges the authorization code for access and refresh tokens, saves the connection details, and redirects to the sync page with a success notice. If any error occurs during the process, logs the error and redirects back to the plugin settings page with an error message.
  def oauth_callback
    QboOauthService.exchange!(code: params[:code], callback_url: callback_url, realm_id: params[:realmId])

    redirect_to qbo_sync_path, flash: { notice: I18n.t(:label_connected) }

  rescue StandardError => e
    log "OAuth failure: #{e.message}"
    redirect_to plugin_settings_path(:redmine_qbo), flash: { error: I18n.t(:label_error) }
  end

  # Manual billing endpoint to trigger the billing process for a specific issue. Validates the issue and its associations, enqueues a job to bill the issue's time entries, and redirects back to the issue with a notice. If validation fails, redirects back with an error message.
  def bill
    issue = Issue.find_by(id: params[:id])
    raise I18n.t(:notice_error_issue_not_found) unless issue
    raise I18n.t(:label_billing_error_no_customer) unless issue.customer
    raise I18n.t(:label_billing_error_no_employee) unless issue.assigned_to&.employee_id.present?
    raise I18n.t(:label_billing_error_no_qbo) unless Qbo.exists?

    BillIssueTimeJob.perform_later(issue.id)

    redirect_to issue, flash: {
      notice: "#{I18n.t(:label_billing_enqueued)} #{issue.customer.name}"
    }

  rescue StandardError => e
    redirect_to issue || root_path, flash: { error: e.message }
  end

  # Manual sync endpoint to trigger a full synchronization of QuickBooks entities with the local database. Enqueues all relevant sync jobs and redirects to the home page with a notice that syncing has started.
  def sync
    QboSyncDispatcher.full_sync!
    redirect_to :home, flash: { notice: I18n.t(:label_syncing) }
  end

  # Endpoint to receive QuickBooks webhook notifications. Validates the request and processes the payload to sync relevant data to Redmine. Responds with appropriate HTTP status codes based on success or failure of processing.
  def webhook
    QboWebhookProcessor.process!(request: request)
    head :ok

  rescue StandardError => e
    log "Webhook failure: #{e.message}"
    head :unauthorized
  end

  private

  # Constructs the OAuth callback URL based on the application's settings and routes. This URL is used during the OAuth flow to redirect users back to the application after authentication with QuickBooks.
  def callback_url
    "#{Setting.protocol}://#{Setting.host_name}#{qbo_oauth_callback_path}"
  end

  # Logs messages with a consistent prefix for easier debugging and monitoring.
  def log(msg)
    Rails.logger.info "[QboController] #{msg}"
  end
end