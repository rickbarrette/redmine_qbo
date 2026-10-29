#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
class InvoicesController < ApplicationController
  include AuthHelper

  # PDFs: logged-in users, or a customer with a share link (limited to their issue's invoices).
  # Redmine's own login check is replaced by require_login_or_customer_token for this action.
  skip_before_action :check_if_login_required, only: :show
  before_action :require_login_or_customer_token, only: :show
  before_action :authorize_customer_invoices, only: :show

  # Syncing is admin-only
  before_action :require_admin, only: :sync

  # Displays the invoice PDF in the browser or redirects with an error if not found.
  def show
    log "Processing request for #{request.original_url}"

    pdf, ref = PdfService.new(entity: Invoice).fetch_pdf(doc_ids: invoice_ids)

    send_data pdf, filename: "invoice #{ref}.pdf", disposition: :inline, type: "application/pdf"

  rescue StandardError => e
    log "Invoice PDF failure: #{e.message}"
    redirect_back fallback_location: root_path, flash: { error: I18n.t(:notice_invoice_not_found) }
  end

  def sync
    Invoice.sync
    redirect_to :home, flash: { notice: I18n.t(:label_syncing) }
  end

  private

  def invoice_ids
    @invoice_ids ||= Array(params[:invoice_ids] || params[:id]).map(&:to_s).reject(&:blank?)
  end

  # Share-link customers may only open invoices attached to their issue
  def authorize_customer_invoices
    return true unless customer_token_only?

    allowed = customer_token.issue&.invoice_ids.to_a.map(&:to_s)
    render_403 if invoice_ids.empty? || (invoice_ids - allowed).any?
  end

  # Logs messages with a consistent prefix for easier debugging.
  def log(msg)
    Rails.logger.info "[InvoiceController] #{msg}"
  end
end