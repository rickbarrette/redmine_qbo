#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class CustomerSyncService
  PAGE_SIZE = 1000

  def initialize(qbo:)
    @qbo = qbo
  end

  # Sync all customers, or only those updated since the last sync
  def sync(full_sync: false)
    log "Starting #{full_sync ? 'full' : 'incremental'} customer sync"

    @qbo.perform_authenticated_request do |access_token|
      service = Quickbooks::Service::Customer.new(company_id: @qbo.realm_id, access_token: access_token)

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

    log "Customer sync complete"
  end

  # Sync a single customer by its QBO ID, used for webhook updates
  def sync_by_id(id)
    @qbo.perform_authenticated_request do |access_token|
      service = Quickbooks::Service::Customer.new(company_id: @qbo.realm_id, access_token: access_token)
      remote = service.fetch_by_id(id)
      persist(remote)
    end
  end

  private

  # Fetch a page of customers, either all or only those updated since the last sync
  def fetch_page(service, page, full_sync)
    start_position = (page - 1) * PAGE_SIZE + 1

    if full_sync
      service.query("SELECT * FROM Customer STARTPOSITION #{start_position} MAXRESULTS #{PAGE_SIZE}")
    else
      last_update = Customer.maximum(:qbo_updated_at) || 1.year.ago
      service.query(<<~SQL.squish)
        SELECT * FROM Customer
        WHERE MetaData.LastUpdatedTime > '#{last_update.utc.iso8601}'
        STARTPOSITION #{start_position}
        MAXRESULTS #{PAGE_SIZE}
      SQL
    end
  end

  # Create or update a local Customer record based on the QBO remote data
  def persist(remote)
    local = Customer.find_or_initialize_by(id: remote.id)

    if remote.active?
      local.name = remote.display_name
      local.phone_number = remote.primary_phone&.free_form_number&.gsub(/\D/, '')
      local.mobile_phone_number = remote.mobile_phone&.free_form_number&.gsub(/\D/, '')

      if local.changed?
        local.save
        log "Updated customer #{remote.id}"
      end
    else
      if local.persisted?
        local.destroy
        log "Deleted customer #{remote.id}"
      end
    end
  rescue => e
    log "Failed to sync customer #{remote.id}: #{e.message}"
  end

  def log(msg)
    Rails.logger.info "[CustomerSyncService] #{msg}"
  end
end