#The MIT License (MIT)
#
#Copyright (c) 2016 rick barrette
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
  
  ::QB_OAUTH_CONSUMER = OAuth::Consumer.new(OAUTH_CONSUMER_KEY, OAUTH_CONSUMER_SECRET, {
      :site                 => "https://oauth.intuit.com",
      :request_token_path   => "/oauth/v1/get_request_token",
      :authorize_url        => "https://appcenter.intuit.com/Connect/Begin",
      :access_token_path    => "/oauth/v1/get_access_token"
    })
    
  # Configure quickbooks-ruby-base to access our database
  Quickbooks::Base.configure do |c|
    c.persistent_token = 'qb_token'
    c.persistent_secret = 'qb_secret'
    c.persistent_company_id =  'company_id'
  end
   
  def self.get_oauth_consumer
    # Quickbooks Config Info
    return QB_OAUTH_CONSUMER
  end

  # Get a quickbooks base object for type
  # @params type of base
  def self.get_base(type)
    Quickbooks::Base.new(first, type)
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
end
