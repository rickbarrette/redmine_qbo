#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module QuickbooksOauth
  extend ActiveSupport::Concern

  #== Instance Methods

  # This method will attempt to execute the block and if it encounters an OAuth2::Error or Quickbooks::AuthorizationFailure it will attempt to refresh the token and retry the block.  It will try this up to 3 times before giving up and raising an exception.
  def perform_authenticated_request(&block)
    attempts = 0
    begin
      yield oauth_access_token
    rescue OAuth2::Error, Quickbooks::AuthorizationFailure => ex
      log "perform_authenticated_request: #{ex.message}"

      # to prevent an infinite loop here keep a counter and bail out after N times...
      attempts += 1

      raise "QuickbooksOauth:ExceededAuthAttempts" if attempts >= 3

      # check if its an invalid_grant first, but assume it is for now
      refresh_token!

      retry
    end
  end

  # This method will attempt to refresh the access token and update the record with the new access token, refresh token and their respective expiration times.  If the refresh token expires in more than 0 seconds then we will set the refresh token expiration time to that value, otherwise we will set it to 100 days from now.
  def refresh_token!
    log "refresh_token!"
    t = oauth_access_token
    refreshed = t.refresh!

    if refreshed.params['x_refresh_token_expires_in'].to_i > 0
      oauth2_refresh_token_expires_at = Time.now + refreshed.params['x_refresh_token_expires_in'].to_i.seconds
    else
      oauth2_refresh_token_expires_at = 100.days.from_now
    end

    log "refresh_token!: #{oauth2_refresh_token_expires_at}"

    update!(
      oauth2_access_token: refreshed.token,
      oauth2_access_token_expires_at: Time.at(refreshed.expires_at),
      oauth2_refresh_token: refreshed.refresh_token,
      oauth2_refresh_token_expires_at: oauth2_refresh_token_expires_at
    )
  end

  # This method will return an instance of the OAuth2::Client class that is configured with the consumer key, consumer secret and the appropriate URLs for the Intuit OAuth2 service.  It will also set the sandbox mode based on the plugin settings.
  def oauth_client
    self.class.construct_oauth2_client
  end

  # This method will return an instance of the OAuth2::AccessToken class that is configured with the current access token, refresh token and the OAuth2 client.  This access token can be used to make authenticated requests to the Intuit API.
  def oauth_access_token
    OAuth2::AccessToken.new(oauth_client, oauth2_access_token, refresh_token: oauth2_refresh_token)
  end

  # This method is an alias for the oauth_access_token method and is used to provide a more intuitive name for the access token when making authenticated requests.
  def consumer
    oauth_access_token
  end

  module ClassMethods

    # This method will construct and return an instance of the OAuth2::Client class that is configured with the consumer key, consumer secret and the appropriate URLs for the Intuit OAuth2 service.  It will also set the sandbox mode based on the plugin settings.  This method is used by the instance method oauth_client to create a new OAuth2 client for each instance of the model that includes this concern.
    def construct_oauth2_client

      oauth_consumer_key = Setting.plugin_redmine_qbo['settingsOAuthConsumerKey']
      oauth_consumer_secret = Setting.plugin_redmine_qbo['settingsOAuthConsumerSecret']

      # Are we are playing in the sandbox?
      Quickbooks.sandbox_mode = Setting.plugin_redmine_qbo[:sandbox] ? true : false
      log "Sandbox mode: #{Quickbooks.sandbox_mode}"

      options = {
        site: "https://appcenter.intuit.com/connect/oauth2",
        authorize_url: "https://appcenter.intuit.com/connect/oauth2",
        token_url: "https://oauth.platform.intuit.com/oauth2/v1/tokens/bearer"
      }
      OAuth2::Client.new(oauth_consumer_key, oauth_consumer_secret, options)
    end

  end


  private

  def log(msg)
    Rails.logger.info "[QuickbooksOauth] #{msg}"
  end
end
