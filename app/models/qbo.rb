#The MIT License (MIT)
#
#Copyright (c) 2017 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class Qbo < ActiveRecord::Base
  unloadable
  validates_presence_of :qb_token, :qb_secret, :company_id, :token_expires_at, :reconnect_token_at
  
  OAUTH_CONSUMER_KEY = Setting.plugin_redmine_qbo['settingsOAuthConsumerKey']
  OAUTH_CONSUMER_SECRET = Setting.plugin_redmine_qbo['settingsOAuthConsumerSecret']
  
  $oauth_params = {
    site: "https://appcenter.intuit.com/connect/oauth2",
    authorize_url: "https://appcenter.intuit.com/connect/oauth2",
    token_url: "https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer"
  }
  oauth2_client = OAuth2::Client.new(OAUTH_CONSUMER_KEY, OAUTH_CONSUMER_SECRET, oauth_params)
  
  def self.get_client
    return oauth2_client
  end
    
  # Configure quickbooks-ruby-base to access our database
  #Quickbooks::Base.configure do |c|
  #  c.persistent_token = 'qb_token'
  #  c.persistent_secret = 'qb_secret'
  #  c.persistent_company_id =  'company_id'
  #end
   
  def self.get_oauth_consumer
    # Quickbooks Config Info
    return $qb_oauth_consumer
  end

  # Get a quickbooks base object for type
  # @params type of base
  def self.get_base(type)
    access_token = OAuth2::AccessToken.new(oauth2_client, qb_secret, refresh_token: qb_secret)
    #get a new refesh token if the current one is too old
    new_access_token_object = access_token.refresh! if refresh_token_expires_at.to_date.past?
    service = Quickbooks::Base.new(first, type)
    service.company_id = company_id # also known as RealmID
    service.access_token = access_token # the OAuth Access Token you have from above
    return service
  end
   
   # Get the QBO account
  def self.get_account
    first
  end
  
  # Updates last sync time stamp
  def self.update_time_stamp
    qbo = Qbo.first
    qbo.last_sync = DateTime.now
    qbo.save
  end
  
  def self.last_sync
    format_time(Qbo.first.last_sync)
  end
end
