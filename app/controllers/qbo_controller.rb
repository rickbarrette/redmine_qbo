#The MIT License (MIT)
#
#Copyright (c) 2016 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class QboController < ApplicationController
  unloadable

  #
  # Called when the QBO Top Menu us shown
  #
  def index
    @qbo = Qbo.first
    @qbo_customer_count = QboCustomer.count
    @qbo_item_count = QboItem.count
    @qbo_employee_count = QboEmployee.count
    @qbo_invoice_count = QboInvoice.count
    @qbo_estimate_count = QboEstimate.count
  end

  #
  # Called when the user requests that Redmine to connect to QBO
  #
  def authenticate
    callback = request.base_url + qbo_oauth_callback_path
    token = Qbo.get_oauth_consumer.get_request_token(:oauth_callback => callback)
    session[:qb_request_token] = token
    redirect_to("https://appcenter.intuit.com/Connect/Begin?oauth_token=#{token.token}") and return
  end

  #
  # Called by QBO after authentication has been processed
  #
  def oauth_callback
    at = session[:qb_request_token].get_access_token(:oauth_verifier => params[:oauth_verifier])
    token = at.token
    secret = at.secret
    realm_id = params['realmId']
    
    #There can only be one...
    Qbo.destroy_all

    # Save the authentication information 
    qbo = Qbo.new
    qbo.token = token
    qbo.secret = secret
    qbo.token_expires_at = 6.months.from_now.utc
    qbo.reconnect_token_at = 5.months.from_now.utc
    qbo.realmId = realm_id
    if qbo.save!
      redirect_to qbo_sync_path, :flash => { :notice => "Successfully connected to Quickbooks" }
    else
      redirect_to plugin_settings_path(:redmine_qbo), :flash => { :error => "Error" }
    end

  end

  #
  # Synchronizes the QboCustomer table with QBO
  #
  def sync
    if Qbo.exists?
      QboCustomer.update_all
      QboItem.update_all
      QboEmployee.update_all
      QboEstimate.update_all
      QboInvoice.update_all
      QboPurchase.update_all
    end

    redirect_to qbo_path(:redmine_qbo), :flash => { :notice => "Successfully synced to Quickbooks" }
  end
end