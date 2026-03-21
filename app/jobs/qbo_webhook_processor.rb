#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class QboWebhookProcessor

  # Processes the incoming QuickBooks webhook request by validating the signature and enqueuing a background job to handle the webhook payload. Raises an error if the signature is invalid.
  def self.process!(request:)
    body = request.raw_post
    signature = request.headers['intuit-signature']
    secret = RedmineQbo.webhook_token_secret

    raise "Invalid signature" unless valid_signature?(body, signature, secret)

    WebhookProcessJob.perform_later(body)
  end

  private

  # Validates the QuickBooks webhook request by computing the HMAC signature and comparing it to the provided signature. Returns false if either the signature or secret is blank, or if the computed signature does not match the provided signature.
  def self.valid_signature?(body, signature, secret)
    return false if signature.blank? || secret.blank?
    log "Validating signature"

    digest = OpenSSL::Digest.new('sha256')
    computed = Base64.strict_encode64(
      OpenSSL::HMAC.digest(digest, secret, body)
    )

    ActiveSupport::SecurityUtils.secure_compare(computed, signature)
  end

  def self.log(msg)
    Rails.logger.info "[QboWebhookProcessor] #{msg}"
  end
end