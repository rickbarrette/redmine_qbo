#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
class InvoiceController < ApplicationController
  include AuthHelper

  before_action :require_user, unless: -> { session[:token].nil? }
  skip_before_action :verify_authenticity_token, :check_if_login_required, unless: -> { session[:token].nil? }

  def show
    log "Processing request for #{request.original_url}"

    invoice_ids = Array(params[:invoice_ids] || params[:id])
    pdf, ref = InvoicePdfService.new(qbo: Qbo.first) .fetch_pdf(invoice_ids: invoice_ids)

    send_data pdf, filename: "invoice #{ref}.pdf", disposition: :inline, type: "application/pdf"

  rescue StandardError => e
    log "Invoice PDF failure: #{e.message}"
    redirect_back fallback_location: root_path, flash: { error: I18n.t(:notice_invoice_not_found) }
  end

  private

  def log(msg)
    Rails.logger.info "[InvoiceController] #{msg}"
  end
end