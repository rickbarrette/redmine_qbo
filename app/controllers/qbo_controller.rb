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
  
  require 'openssl'
  
  include AuthHelper
  
  before_action :require_user, except: :webhook
  skip_before_action :verify_authenticity_token, :check_if_login_required, only: [:webhook]

  def allowed_params
    params.permit(:code, :state, :realmId, :id)
  end

  #
  # Called when the user requests that Redmine to connect to QBO
  #
  def authenticate
    redirect_uri = "#{Setting.protocol}://#{Setting.host_name + qbo_oauth_callback_path}"
    logger.info "redirect_uri: #{redirect_uri}"
    oauth2_client = Qbo.construct_oauth2_client
    grant_url = oauth2_client.auth_code.authorize_url(redirect_uri: redirect_uri, response_type: "code", state: SecureRandom.hex(12), scope: "com.intuit.quickbooks.accounting")
    redirect_to grant_url
  end
  
  #
  # Called by QBO after authentication has been processed
  #
  def oauth_callback
    if params[:state].present?
      oauth2_client = Qbo.construct_oauth2_client
      # use the state value to retrieve from your backend any information you need to identify the customer in your system
      redirect_uri = "#{Setting.protocol}://#{Setting.host_name + qbo_oauth_callback_path}"
      if resp = oauth2_client.auth_code.get_token(params[:code], redirect_uri: redirect_uri)
        
        # Remove the last authentication information
        Qbo.delete_all
        
        # Save the authentication information 
        qbo = Qbo.new
        qbo.update(oauth2_access_token: resp.token, oauth2_refresh_token: resp.refresh_token, realm_id: params[:realmId])
        qbo.refresh_token!
        
        if qbo.save!
          redirect_to qbo_sync_path, flash: { notice: I18n.t(:label_connected) }
        else
          redirect_to plugin_settings_path(:redmine_qbo), flash: { error: I18n.t(:label_error) }
        end
        
      end
    end
  end
  
  # Manual Billing
  def bill
    i = Issue.find_by_id params[:id]
    if i.customer
      i.bill_time
      redirect_to i, flash: { notice: I18n.t(:label_billed_success) + i.customer.name }
    else
      redirect_to i, flash: { error: I18n.t(:label_billing_error) }
    end
  end
  
  # Quickbooks Webhook Callback
  def webhook

    logger.info "Quickbooks is calling webhook"
    
    # check the payload
    signature = request.headers['intuit-signature']
    key = Setting.plugin_redmine_qbo['settingsWebhookToken']
    data = request.body.read
    hash = Base64.encode64(OpenSSL::HMAC.digest(OpenSSL::Digest::Digest.new('sha256'), key, data)).strip()
    
    # proceed if the request is good
    if hash.eql? signature
      Thread.new do
        if request.headers['content-type'] == 'application/json'
          data = JSON.parse(data)
        else
          # application/x-www-form-urlencoded
          data = params.as_json
        end
        # Process the information
        entities = data['eventNotifications'][0]['dataChangeEvent'][:entities]
        entities.each do |entity|
          id = entity[:id].to_i
          name = entity[:name]
        
          logger.info "Casting #{name.constantize} to obj"

          # Magicly initialize the correct class
          obj = name.constantize

          # for merge events
          obj.destroy(entity['deletedId']) if entity['deletedId']
          
          #Check to see if we are deleting a record
          if entity[:operation].eql? "Delete"
            obj.destroy(id)
          #if not then update!
          else
            begin
              obj.sync_by_id(id)
            rescue => e
              logger.error "Failed to call sync_by_id on obj"
              logger.error e.message
              logger.error e.backtrace.join("\n")
            end
          end
        end
        
        # Record that last time we updated
        Qbo.update_time_stamp
        ActiveRecord::Base.connection.close
      end
      # The webhook doesn't require a response but let's make sure we don't send anything
      render nothing: true, status: 200
    else
      render nothing: true, status: 400
    end

    logger.info "Quickbooks webhook complete"
  end

  #
  # Synchronizes the QboCustomer table with QBO
  #
  def sync
    logger.info "Syncing EVERYTHING"
    # Update info in background
    Thread.new do
      if Qbo.exists?
        Customer.sync
        Invoice.sync
        Employee.sync
        Estimate.sync
        
        # Record the last sync time
        Qbo.update_time_stamp
      end
      ActiveRecord::Base.connection.close
    end

    redirect_to :home, flash: { notice: I18n.t(:label_syncing) }
  end
end
