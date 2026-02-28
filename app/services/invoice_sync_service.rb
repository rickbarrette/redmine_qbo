#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class InvoiceSyncService
  PAGE_SIZE = 1000

  def initialize(qbo:)
    @qbo = qbo
  end

  # Sync all invoices, or only those updated since the last sync
  def sync(full_sync: false)
    log "Starting #{full_sync ? 'full' : 'incremental'} invoice sync"

    @qbo.perform_authenticated_request do |access_token|
      service = Quickbooks::Service::Invoice.new(company_id: @qbo.realm_id, access_token: access_token)

      page = 1
      loop do
        collection = fetch_page(service, page, full_sync)
        entries = Array(collection&.entries)
        break if entries.empty?

        entries.each { |remote| persist(remote) }

        break if entries.size < PAGE_SIZE
        page += 1
      end
    end

    log "Invoice sync complete"
  end

  # Sync a single invoice by its QBO ID, used for webhook updates
  def sync_by_id(id)
    @qbo.perform_authenticated_request do |access_token|
      service = Quickbooks::Service::Invoice.new(company_id: @qbo.realm_id, access_token: access_token)
      remote = service.fetch_by_id(id)
      persist(remote)
    end
  end

  private

  # Fetch a page of invoices, either all or only those updated since the last sync
  def fetch_page(service, page, full_sync)
    start_position = (page - 1) * PAGE_SIZE + 1

    if full_sync
      service.query("SELECT * FROM Invoice STARTPOSITION #{start_position} MAXRESULTS #{PAGE_SIZE}")
    else
      last_update = Invoice.maximum(:qbo_updated_at) || 1.year.ago
      service.query(<<~SQL.squish)
        SELECT * FROM Invoice
        WHERE MetaData.LastUpdatedTime > '#{last_update.utc.iso8601}'
        STARTPOSITION #{start_position}
        MAXRESULTS #{PAGE_SIZE}
      SQL
    end
  end

  # Create or update a local Invoice record based on the QBO remote data
  def persist(remote)
    invoice = Invoice.find_or_initialize_by(id: remote.id)

    invoice.doc_number      = remote.doc_number
    invoice.txn_date        = remote.txn_date
    invoice.due_date        = remote.due_date
    invoice.total_amount    = remote.total
    invoice.balance         = remote.balance
    invoice.qbo_updated_at  = remote.meta_data&.last_updated_time

    invoice.customer = Customer.find_by(id: remote.customer_ref&.value)

    invoice.save!

    InvoiceAttachmentService.new(invoice, remote).attach
  end

  def log(msg)
    Rails.logger.info "[InvoiceSyncService] #{msg}"
  end
end