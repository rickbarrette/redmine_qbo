#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class EstimateSyncService
  PAGE_SIZE = 1000

  def initialize(qbo:)
    @qbo = qbo
  end

  # Sync all estimates, or only those updated since the last sync
  def sync(full_sync: false)
    log "Starting #{full_sync ? 'full' : 'incremental'} estimate sync"

    @qbo.perform_authenticated_request do |access_token|
      service = Quickbooks::Service::Estimate.new(company_id: @qbo.realm_id, access_token: access_token)

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

    log "Estimate sync complete"
  end

  # Sync a single estimate by its QBO ID, used for webhook updates
  def sync_by_doc(doc_number)
    log "Syncing estimate by doc_number: #{doc_number}"
    @qbo.perform_authenticated_request do |access_token|
      service = Quickbooks::Service::Estimate.new(company_id: @qbo.realm_id, access_token: access_token)
      remote = service.find_by( :doc_number, doc_number).first
      log "Found estimate with ID #{remote.id} for doc_number #{doc_number}" if remote
      persist(remote)
    end
  end

  # Sync a single estimate by its QBO ID, used for webhook updates
  def sync_by_id(id)
    log "Syncing estimate by ID: #{id}"
    @qbo.perform_authenticated_request do |access_token|
      service = Quickbooks::Service::Estimate.new(company_id: @qbo.realm_id, access_token: access_token)
      remote = service.fetch_by_id(id)
      persist(remote)
    end
  end

  private

  # Fetch a page of estimates, either all or only those updated since the last sync
  def fetch_page(service, page, full_sync)
    log "Fetching page #{page} of estimates (full_sync: #{full_sync})"
    start_position = (page - 1) * PAGE_SIZE + 1

    if full_sync
      service.query("SELECT * FROM Estimate STARTPOSITION #{start_position} MAXRESULTS #{PAGE_SIZE}")
    else
      last_update = Estimate.maximum(:updated_at) || 1.year.ago
      service.query(<<~SQL.squish)
        SELECT * FROM Estimate
        WHERE MetaData.LastUpdatedTime > '#{last_update.utc.iso8601}'
        STARTPOSITION #{start_position}
        MAXRESULTS #{PAGE_SIZE}
      SQL
    end
  end

  # Create or update a local Estimate record based on the QBO remote data
  def persist(remote)
    log "Persisting estimate #{remote.id}"
    local = Estimate.find_or_initialize_by(id: remote.id)

    local.doc_number = remote.doc_number
    local.txn_date = remote.txn_date
    local.customer = Customer.find_by(id: remote.customer_ref&.value)
    
    if local.changed?
      local.save
      log "Updated estimate #{remote.id}"
    end
  rescue => e
    log "Failed to sync estimate #{remote.id}: #{e.message}"
  end

  def log(msg)
    Rails.logger.info "[EstimateSyncService] #{msg}"
  end
end