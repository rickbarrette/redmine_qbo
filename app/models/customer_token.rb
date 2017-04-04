#The MIT License (MIT)
#
#Copyright (c) 2017 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class CustomerToken < ActiveRecord::Base
  unloadable
  has_many :issues
  attr_accessible :token, :expires_at, :issue_id
  validates_presence_of :expires_at, :issue_id
  before_create :generate_token

  OAUTH_CONSUMER_SECRET = Setting.plugin_redmine_qbo['settingsOAuthConsumerSecret'] || 'CONFIGURE_QBO__' + SecureRandom.uuid
  
  def generate_token
    self.token = SecureRandom.base64(15).tr('+/=lIO0', OAUTH_CONSUMER_SECRET)
  end
end
