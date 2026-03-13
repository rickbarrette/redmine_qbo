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
    with_qbo_service do |service|
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
    with_qbo_service do |service|
      remote = service.fetch_by_id(id)
      persist(remote)
    end
  end

  private

  def attach_documents(local, remote)
    # Override in subclasses if the entity has attachments (e.g. Invoice)
  end

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

  # Determine if a remote entity should be deleted locally (e.g. if it's marked inactive in QBO)
  def destroy_local?(remote)
    false
  end

  def extract_value(remote, remote_attr)
    case remote_attr
    when Proc
      remote_attr.call(remote)
    else
      remote.public_send(remote_attr)
    end
  end

  # Attribute Mapping DSL
  #
  # This DSL defines how attributes from a QuickBooks Online (QBO) entity
  # are mapped onto a local ActiveRecord model during synchronization.
  #
  # Each mapping registers a lambda in `attribute_map`. When a remote QBO
  # object is processed, the lambda is executed to extract and transform
  # the value that will be assigned to the local model attribute.
  #
  # The DSL supports several mapping patterns:
  #
  # 1. Direct attribute mapping (same name)
  #
  #      map_attribute :doc_number
  #
  #    Equivalent to:
  #
  #      local.doc_number = remote.doc_number
  #
  # 2. Renamed attribute mapping
  #
  #      map_attribute :total_amount, :total
  #
  #    Equivalent to:
  #
  #      local.total_amount = remote.total
  #
  # 3. Custom transformation logic
  #
  #      map_attribute :qbo_updated_at do |remote|
  #        remote.meta_data&.last_updated_time
  #      end
  #
  #    Useful for nested fields or computed values.
  #
  # 4. Bulk attribute mapping
  #
  #      map_attributes :doc_number, :txn_date, :due_date
  #
  #    Convenience helper that maps multiple attributes with identical names.
  #
  # 5. Foreign key / reference mapping
  #
  #      map_belongs_to :customer
  #
  #    Resolves a QBO reference object (e.g. `customer_ref.value`) and finds
  #    the associated local ActiveRecord model.
  #
  # 6. Specialized helpers
  #
  #      map_phone :phone_number, :primary_phone
  #
  #    Extracts and normalizes phone numbers by stripping non-digit characters.
  #
  # Internally, the mappings are stored in `attribute_map` and executed by the
  # SyncService during `process_attributes`, which iterates through each mapping
  # and assigns the computed value to the local record.
  #
  # This design keeps synchronization services declarative, readable, and easy
  # to extend while centralizing transformation logic in a single DSL.
  class << self

    def map_attributes(*attrs)
      attrs.each do |attr|
        map_attribute(attr)
      end
    end


    def map_attribute(local_attr, remote_attr = nil, &block)
      attribute_map[local_attr] =
        if block_given?
          block
        elsif remote_attr
          ->(remote) do
            remote_attr.to_s.split('.').reduce(remote) do |obj, method|
              obj&.public_send(method)
            end
          end
        else
          ->(remote) { remote.public_send(local_attr) }
        end
    end

    def attribute_map
      @attribute_map ||= {}
    end

    def map_belongs_to(local_attr, ref: nil, model: nil)
      ref ||= "#{local_attr}_ref"
      model ||= local_attr.to_s.classify.constantize

      attribute_map[local_attr] = lambda do |remote|
        ref_obj = remote.public_send(ref)
        id = ref_obj&.value
        id ? model.find_by(id: id) : nil
      end
    end

    def map_phone(local_attr, remote_attr)
      attribute_map[local_attr] = lambda do |remote|
        phone = remote.public_send(remote_attr)
        phone&.free_form_number&.gsub(/\D/, '')
      end
    end
  end

  # Log messages with the entity type for better traceability
  def log(msg)
    Rails.logger.info "[#{@entity.name}SyncService] #{msg}"
  end

  # Create or update a local entity record based on the QBO remote data
  def persist(remote)
    local = @entity.find_or_initialize_by(id: remote.id)
    
    if destroy_local?(remote)
      if local.persisted?
        local.destroy
        log "Deleted #{@entity.name} #{remote.id}"
      end
      return
    end

    process_attributes(local, remote)
    
    if local.new_record? || local.changed?
      was_new = local.new_record?
      local.skip_qbo_push = true
      local.save!
      log "#{was_new ? 'Created' : 'Updated'} #{@entity.name} #{remote.id}"
      attach_documents(local, remote)
    end

  rescue => e
    log "Failed to sync #{@entity.name} #{remote.id}: #{e.message}"
  end

  # Maps remote attributes to local model
  def process_attributes(local, remote)
    log "Processing #{@entity} ##{remote.id}"

    self.class.attribute_map.each do |local_attr, mapper|
      value = mapper.call(remote)

      if local.public_send(local_attr) != value
        local.public_send("#{local_attr}=", value)
      end
    end
  end

  # Dynamically get the Quickbooks Service Class
  def service_class
    @service_class ||= "Quickbooks::Service::#{@entity}".constantize
  end

  # Performs authenticaed requests with QBO service
  def with_qbo_service
    @qbo.perform_authenticated_request do |access_token|
      service = service_class.new( company_id: @qbo.realm_id, access_token: access_token )
      yield service
    end
  end
end