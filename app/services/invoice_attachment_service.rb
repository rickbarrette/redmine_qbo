#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class InvoiceAttachmentService

  def initialize(invoice, remote)
    @invoice = invoice
    @remote  = remote
  end

  # Attach invoice to issues based on issue IDs found in the invoice's private note and line descriptions
  def attach
    extract_issue_ids.each do |issue_id|
      log "Processing issue ##{issue_id} for invoice ##{@invoice.doc_number}"
      
      issue = Issue.find_by(id: issue_id)
      next unless issue
      next unless issue.customer&.id == @invoice.customer&.id

      unless issue.invoices.exists?(@invoice.id)
        issue.invoices << @invoice
        issue.save! if issue.changed?
        log "Attached invoice ##{@invoice.id} to issue ##{issue.id}"
      end

      InvoiceCustomFieldSyncService.new(issue, @invoice, @remote).sync
    end
  end

  private

  # Extract issue IDs from the invoice's private note and line descriptions
  def extract_issue_ids
    ids = []

    if @remote.private_note.present?
      ids += scan(@remote.private_note)
    end

    Array(@remote.line_items).each do |line|
      ids += scan(line.description.to_s)
    end

    ids.uniq
  end

  # Scan text for issue IDs in the format #123
  def scan(text)
    text.scan(/#(\d+)/).flatten.map(&:to_i)
  end

  def log(msg)
    Rails.logger.info "[InvoiceAttachmentService] #{msg}"
  end
end