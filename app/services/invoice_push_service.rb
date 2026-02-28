#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class InvoicePushService
  
  def initialize(invoice)
    @invoice = invoice
  end

  # Push invoice changes to QBO if the invoice is linked to any issues with custom field changes that need to be synced
  def push
    return if @invoice.qbo_sync_locked?

    log "Pushing invoice ##{@invoice.id} to QBO due to linked issue custom field changes"

    @invoice.update_column(:qbo_sync_locked, true)

    qbo = Qbo.first

    qbo.perform_authenticated_request do |access_token|
      service = Quickbooks::Service::Invoice.new( company_id: qbo.realm_id, access_token: access_token)

      remote = service.fetch_by_id(@invoice.id)

      # modify remote object here if needed

      service.update(remote)
    end
  rescue => e
    Rails.logger.error "[InvoicePushService] #{e.message}"
  ensure
    @invoice.update_column(:qbo_sync_locked, false)
  end

  private

  def log(msg)
    Rails.logger.info "[InvoicePushService] #{msg}"
  end
end