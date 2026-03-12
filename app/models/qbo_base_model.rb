#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class QboBaseModel < ActiveRecord::Base

  include Redmine::I18n

  self.abstract_class = true
  validates_presence_of :id

  # Returns the details of the entity. 
  # If the details have already been fetched, it returns the cached version. 
  # Otherwise, it fetches the details from QuickBooks Online and caches them for future use. 
  # This method is used to access the entity's information in a way that minimizes unnecessary API calls to QBO, improving performance and reducing latency.
  def details
    @details ||= begin
      xml = Rails.cache.fetch(details_cache_key, expires_in: 10.minutes) do
        fetch_details.to_xml_ns
      end
      model_class = "Quickbooks::Model::#{model_name.name}".constantize
      model_class.from_xml(xml)
    end
  end

   # Generates a unique cache key for storing this customer's QBO details.
  def details_cache_key
    "#{model_name.name}:#{id}:qbo_details:#{updated_at.to_i}"
  end


  # Returns the last sync time formatted for display. 
  # If no sync has occurred, returns a default message.
  def self.last_sync
    return I18n.t(:label_qbo_never_synced) unless maximum(:updated_at)
    format_time(maximum(:updated_at))
  end

  # Magic Method
  # Maps Get/Set methods to QBO entity object
  def method_missing(method_name, *args, &block)
    model_class = "Quickbooks::Model::#{model_name.name}".constantize
    if model_class.method_defined?(method_name)
      details
      @details.public_send(method_name, *args, &block)
    else
      super
    end
  end

  # Repsonds to missing methods by delegating to the QBO customer details object if the method is defined there.
  # This allows for dynamic access to any attributes or methods of the QBO customer without having to explicitly define them in the Subclass model, providing flexibility and reducing boilerplate code.
  def respond_to_missing?(method_name, include_private = false)
    model_class = "Quickbooks::Model::#{model_name.name}".constantize
    model_class.method_defined?(method_name) || super
  end

  # Sync all entities, typically triggered by a scheduled task or manual sync request
  def self.sync
    job = "#{model_name.name}SyncJob".constantize
    job.perform_later(full_sync: true)
  end

  # Sync a single entity by ID, typically triggered by a webhook notification or manual sync request
  def self.sync_by_id(id)
    job = "#{model_name.name}SyncJob".constantize
    job.perform_later(id: id)
  end

  # Push the updates
  def save_with_push
    log "Starting push for #{model_name.name} ##{self.id}..."
    qbo = QboConnectionService.current!
    service = "#{model_name.name}Service".constantize
    service.new(qbo: qbo, remote: self).push()
    Rails.cache.delete(details_cache_key)
    save_without_push
  end

   alias_method :save_without_push, :save
   alias_method :save, :save_with_push

  private
  
  def log(msg)
    Rails.logger.info "[#{model_name.name}] #{msg}"
  end

  # Fetches the entity's details from QuickBooks Online. 
  def fetch_details
    log "Fetching details for #{model_name.name} ##{id} from QBO..."
    qbo = QboConnectionService.current!
    service_class = "#{model_name.name}Service".constantize
    service_class.new(qbo: qbo, remote: self).pull()
  end

end