#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class SyncServiceBase
  PAGE_SIZE = 1000

  # Subclasses should initialize with a QBO client instance
  def initialize(qbo:)
    raise "No QBO configuration found" unless qbo
    @qbo = qbo
    @entity = self.class.model_class
    @page_size = self.class.page_size 
  end

  # Subclasses can implement this to overide the default page size
  def self.page_size
    @page_size = PAGE_SIZE
  end

  # Subclasses must implement this to specify which local model they sync (e.g. Customer, Invoice)
  def self.model_class
    raise NotImplementedError
  end

  # Sync all entities, or only those updated since the last sync
  def sync(full_sync: false)
    log "Starting #{full_sync ? 'full' : 'incremental'} #{@entity.name} sync with page size of: #{@page_size}"

    @qbo.perform_authenticated_request do |access_token|
      service_class = "Quickbooks::Service::#{@entity.name}".constantize
      service = service_class.new(company_id: @qbo.realm_id, access_token: access_token)

      query = build_query(full_sync)

      service.query_in_batches(query, per_page: @page_size) do |batch|
        entries = Array(batch)
        log "Processing batch of #{entries.size} #{@entity.name}"

        entries.each do |remote|
          persist(remote)
        end
      end
    end

    log "#{@entity.name} sync complete"
  end

  # Sync a single entity by its QBO ID (webhook usage)
  def sync_by_id(id)
    log "Syncing #{@entity.name} with ID #{id}"

    @qbo.perform_authenticated_request do |access_token|
      service_class = "Quickbooks::Service::#{@entity.name}".constantize
      service = service_class.new(company_id: @qbo.realm_id, access_token: access_token)
      remote = service.fetch_by_id(id)
      persist(remote)
    end
  end

  private

  # Builds a QBO query for retrieving entities
  def build_query(full_sync)
    if full_sync
      "SELECT * FROM #{@entity.name} ORDER BY Id"
    else
      last_update = @entity.maximum(:updated_at) || 1.year.ago

      <<~SQL.squish
        SELECT * FROM #{@entity.name}
        WHERE MetaData.LastUpdatedTime > '#{last_update.utc.iso8601}'
        ORDER BY MetaData.LastUpdatedTime
      SQL
    end
  end

  def attach_documents(local, remote)
    # Override in subclasses if the entity has attachments (e.g. Invoice)
  end

  # Determine if a remote entity should be deleted locally (e.g. if it's marked inactive in QBO)
  def destroy_remote?(remote)
    false
  end

  # Log messages with the entity type for better traceability
  def log(msg)
    Rails.logger.info "[#{@entity.name}SyncService] #{msg}"
  end

  # Create or update a local entity record based on the QBO remote data
  def persist(remote)
    local = @entity.find_or_initialize_by(id: remote.id)

    if destroy_remote?(remote)
      if local.persisted?
        local.destroy
        log "Deleted #{@entity.name} #{remote.id}"
      end
      return
    end

    process_attributes(local, remote)

    if local.changed?
      local.skip_qbo_push = true
      local.save
      log "Updated #{@entity.name} #{remote.id}"
      attach_documents(local, remote)
    end

  rescue => e
    log "Failed to sync #{@entity.name} #{remote.id}: #{e.message}"
  end

  # This method should be implemented in subclasses to map remote attributes to local model
  def process_attributes(local, remote)
    raise NotImplementedError, "Subclasses must implement process_attributes"
  end
end