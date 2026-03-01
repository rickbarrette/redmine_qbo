#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
class InvoicePdfService
  
  require 'combine_pdf'

  def initialize(qbo:)
    @qbo = qbo
  end

  # Fetches the PDF for the given invoice IDs. If multiple IDs are provided, their PDFs are combined into a single document.
  def fetch_pdf(invoice_ids:)
    log "Fetching PDFs for invoice IDs: #{invoice_ids.join(', ')}"
    @qbo.perform_authenticated_request do |access_token|
      service = Quickbooks::Service::Invoice.new(
        company_id: @qbo.realm_id,
        access_token: access_token
      )

      return single_pdf(service, invoice_ids.first) if invoice_ids.size == 1

      combined_pdf(service, invoice_ids)
    end
  end

  private

  # Fetches a single PDF for the given invoice ID.
  def single_pdf(service, id)
    log "Fetching PDF for invoice ID: #{id}"
    invoice = service.fetch_by_id(id)
    [service.pdf(invoice), invoice.doc_number]
  end

  # Combines PDFs for multiple invoice IDs into a single PDF document and returns it along with a reference string.
  def combined_pdf(service, ids)
    log "Combining PDFs for invoice IDs: #{ids.join(', ')}"
    pdf = CombinePDF.new
    ref = []

    ids.each do |id|
      invoice = service.fetch_by_id(id)
      ref << invoice.doc_number
      pdf << CombinePDF.parse(service.pdf(invoice))
    end

    [pdf.to_pdf, ref.join(" ")]
  end

  def log(msg)
    Rails.logger.info "[InvoicePdfService] #{msg}"
  end
end