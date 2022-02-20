#The MIT License (MIT)
#
#Copyright (c) 2022 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class QboController < ApplicationController
  unloadable
  
  require 'openssl'
  
  include AuthHelper
  
  before_action :require_user, :except => :qbo_webhook
  skip_before_action :verify_authenticity_token, :check_if_login_required, :only => [:qbo_webhook]

  def allowed_params
    params.permit(:code, :state, :realmId, :id)
  end

  #
  # Called when the QBO Top Menu us shown
  #
  def index
    @qbo = Qbo.first
    @customer_count = Customer.count
    @qbo_item_count = QboItem.count
    @qbo_employee_count = QboEmployee.count
    @qbo_invoice_count = QboInvoice.count
    @qbo_estimate_count = QboEstimate.count
  end

  #
  # Called when the user requests that Redmine to connect to QBO
  #
  def authenticate
    oauth2_client = Qbo.get_client
    callback = Setting.host_name + "/qbo/oauth_callback/" 
    #callback = qbo_oauth_callback_url
    grant_url = oauth2_client.auth_code.authorize_url(redirect_uri: callback, response_type: "code", state: SecureRandom.hex(12), scope: "com.intuit.quickbooks.accounting")
    redirect_to grant_url
  end
  
  #
  # Called by QBO after authentication has been processed
  #
  def oauth_callback
    if params[:state].present?
      oauth2_client = Qbo.get_client
      # use the state value to retrieve from your backend any information you need to identify the customer in your system
      #redirect_uri = qbo_oauth_callback_url
      redirect_uri = Setting.host_name + "/qbo/oauth_callback/"
      if resp = oauth2_client.auth_code.get_token(params[:code], redirect_uri: redirect_uri)
        
        # Remove the last authentication information
        Qbo.delete_all
        
        # Save the authentication information 
        qbo = Qbo.new
        qbo.company_id = params[:realmId]
        
        # Generate Access Token & Serialize it into the database
        access_token = OAuth2::AccessToken.new(oauth2_client, resp.token, refresh_token: resp.refresh_token)
        qbo.token = access_token.to_hash
        qbo.expire = 1.hour.from_now.utc
        
        if qbo.save!
          redirect_to qbo_sync_path, :flash => { :notice => "Successfully connected to Quickbooks" }
        else
          redirect_to plugin_settings_path(:redmine_qbo), :flash => { :error => "Error" }
        end
        
      end
    end
  end
  
  # Manual Billing
  def bill
    i = Issue.find_by_id params[:id]
    if i.customer
      i.bill_time
      redirect_to i, :flash => { :notice => "Successfully Billed #{i.customer.name}" }
    else
      redirect_to i, :flash => { :error => "Cannot bill without a customer assigned" }
    end
  end
  
  # Quickbooks Webhook Callback
  def qbo_webhook

    logger.debug "Quickbooks is calling webhook"
    
    # check the payload
    signature = request.headers['intuit-signature']
    key = Setting.plugin_redmine_qbo['settingsWebhookToken']
    data = request.body.read
    hash = Base64.encode64(OpenSSL::HMAC.digest(OpenSSL::Digest::Digest.new('sha256'), key, data)).strip()
    
    # proceed if the request is good
    if hash.eql? signature
      if request.headers['content-type'] == 'application/json'
        data = JSON.parse(data)
      else
        # application/x-www-form-urlencoded
        data = params.as_json
      end
      # Process the information
      entities = data['eventNotifications'][0]['dataChangeEvent']['entities']
      entities.each do |entity|
        id = entity['id'].to_i
        name = entity['name']
        
        # TODO rename all other models!
        name.prepend("Qbo") if not name.eql? "Customer"
       
        logger.debug "Casting #{name.constantize} to obj"

        # Magicly initialize the correct class
        obj = name.constantize

        # for merge events
        obj.destroy(entity['deletedId']) if entity['deletedId']
        
        #Check to see if we are deleting a record
        if entity['operation'].eql? "Delete"
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
      
      # The webhook doesn't require a response but let's make sure we don't send anything
      render :nothing => true
    else
      render nothing: true, status: 400
    end

    logger.debug "Quickbooks webhook complete"
  end

  #
  # Synchronizes the QboCustomer table with QBO
  #
  def sync
    logger.debug "Syncing EVERYTHING"
    # Update info in background
    Thread.new do
      if Qbo.exists?
        Customer.sync
        QboInvoice.sync
        QboItem.sync
        QboEmployee.sync
        QboEstimate.sync
        
        # Record the last sync time
        Qbo.update_time_stamp
      end
      ActiveRecord::Base.connection.close
    end

    redirect_to :home, :flash => { :notice => "Successfully synced to Quickbooks" }
  end
end
