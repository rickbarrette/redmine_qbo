#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
class PdfService
  
  require 'combine_pdf'

  # Subclasses should initialize with a QBO client instance
  def initialize(entity: entity)
    raise "An entity to sync is required" unless entity
    @entity = entity
  end

  # Fetches the PDF for the given entity IDs. If multiple IDs are provided, their PDFs are combined into a single document.
  def fetch_pdf(doc_ids:)
    log "Fetching PDFs for #{@entity} IDs: #{doc_ids.join(', ')}"
    QboConnectionService.with_qbo_service(entity: @entity) do |service|
      return single_pdf(service, doc_ids.first) if doc_ids.size == 1
      combined_pdf(service, doc_ids)
    end
  end

  private

  # Fetches a single PDF for the given invoice ID.
  def single_pdf(service, id)
    log "Fetching PDF for #{@entity} ID: #{id}"
    entity = service.fetch_by_id(id)
    [service.pdf(entity), entity.doc_number]
  end

  # Combines PDFs for multiple entity IDs into a single PDF document and returns it along with a reference string.
  def combined_pdf(service, ids)
    log "Combining PDFs for #{@entity} IDs: #{ids.join(', ')}"
    pdf = CombinePDF.new
    ref = []

    ids.each do |id|
      entity = service.fetch_by_id(id)
      ref << entity.doc_number
      pdf << CombinePDF.parse(service.pdf(entity))
    end

    [pdf.to_pdf, ref.join(" ")]
  end

  # Logs messages with a consistent prefix for easier debugging.
  def log(msg)
    Rails.logger.info "[#{@entity}PdfService] #{msg}"
  end
end