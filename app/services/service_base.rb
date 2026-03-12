#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class ServiceBase

  # Subclasses should Initializes the service with a QBO client and a local record. 
  # The QBO client is used to communicate with QuickBooks Online, while the local record contains the data that needs to be pushed to QBO. 
  # If no local is provided, the service will not perform any operations.
  def initialize(qbo:, local: nil)
    @entity = local.class.name
    raise "No QBO configuration found" unless qbo
    raise "#{@entity} record is required for push operation" unless local
    @qbo = qbo
    @local = local
  end

  # Subclasses must implement this to build a new QBO entity if a remote is not found
  def build_qbo_remote
    raise NotImplementedError
  end

  # Pulls the Item data from QuickBooks Online. 
  def pull
    return build_qbo_remote unless @local.present?
    return build_qbo_remote unless @local.id
    log "Fetching details for #{@entity} ##{@local.id} from QBO..."
    with_qbo_service do |service|
      service.fetch_by_id(@local.id)
    end
  rescue => e
    log "Fetch failed for #{@local.id}: #{e.message}"
    build_qbo_remote
  end

   # Pushes the Item data to QuickBooks Online. 
   # This method handles the communication with QBO, including authentication and error handling. 
   # It uses the QBO client to send the remote data and logs the process for monitoring and debugging purposes. 
   # If the push is successful, it returns the remote record; otherwise, it logs the error and returns false.
  def push
    log "Pushing #{@entity} ##{@local.id} to QBO..."
    remote = with_qbo_service do |service|
      if @local.id.present?
        log "Updating #{@entity}"
        service.update(@local.details)
      else
        log "Creating #{@entity}"
        service.create(@local.details)
      end
    end
    @local.id = remote.id unless @local.persisted?
    log "Push for remote ##{@local.id} completed."
    @local
  end

  private 

  # Performs authenticaed requests with QBO service
  def with_qbo_service
    @qbo.perform_authenticated_request do |access_token|
      service = service_class.new( company_id: @qbo.realm_id, access_token: access_token )
      yield service
    end
  end

  # Log messages with the entity type for better traceability
  def log(msg)
    Rails.logger.info "[#{@entity}Service] #{msg}"
  end

  # Dynamically get the Quickbooks Service Class
  def service_class
    @service_class ||= "Quickbooks::Service::#{@entity}".constantize
  end

end