#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class QboOauthService

  # Generates the QuickBooks OAuth authorization URL with the specified callback URL. The URL includes necessary parameters such as response type, state, and scope.
  def self.authorization_url(callback_url:)
    client.auth_code.authorize_url(
      redirect_uri: callback_url,
      response_type: "code",
      state: SecureRandom.hex(12),
      scope: "com.intuit.quickbooks.accounting"
    )
  end

  # Exchanges the authorization code for access and refresh tokens. Creates or replaces the QBO connection record with the new credentials and refreshes the token immediately after creation.
  def self.exchange!(code:, callback_url:, realm_id:)
    resp = client.auth_code.get_token(code, redirect_uri: callback_url)
    QboConnectionService.replace!( token: resp.token, refresh_token: resp.refresh_token, realm_id: realm_id )
  end

  # Constructs and returns an OAuth2 client instance configured with the application's credentials and settings.
  def self.client
    Qbo.construct_oauth2_client
  end
end