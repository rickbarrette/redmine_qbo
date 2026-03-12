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

  # Subclasses should Initializes the service with a QBO client and an optional remote record. 
  # The QBO client is used to communicate with QuickBooks Online, while the local record contains the data that needs to be pushed to QBO. 
  # If no remote is provided, the service will not perform any operations.
  def initialize(qbo:, remote: nil)
    raise "No QBO configuration found" unless qbo
    raise "#{@entity} record is required for push operation" unless remote
    @qbo = qbo
    @entity = remote.class.name
    @remote = remote
  end

  # # Subclasses must implement this to specify which local model they sync (e.g. Customer, Invoice)
  # def self.model_class
  #   raise NotImplementedError
  # end

  # Subclasses must implement this to build a new QBO entity if a remote is not found
  def build_qbo_remote
    raise NotImplementedError
  end

  # Pulls the Item data from QuickBooks Online. 
  def pull
    return build_qbo_remote unless @remote.present?
    return build_qbo_remote unless @remote.id
    log "Fetching details for #{@entity} ##{@remote.id} from QBO..."
    qbo = QboConnectionService.current!
    qbo.perform_authenticated_request do |access_token|
      service_class = "Quickbooks::Service::#{@entity}".constantize
      service = service_class.new(
        company_id: qbo.realm_id,
        access_token: access_token
      )
      service.fetch_by_id(@remote.id)
    end
  rescue => e
    log "Fetch failed for #{@remote.id}: #{e.message}"
    build_qbo_remote
  end

   # Pushes the Item data to QuickBooks Online. This method handles the communication with QBO, including authentication and error handling. It uses the QBO client to send the remote data and logs the process for monitoring and debugging purposes. If the push is successful, it returns the remote record; otherwise, it logs the error and returns false.
  def push
    log "Pushing #{@entity} ##{@remote.id} to QBO..."

    remote = @qbo.perform_authenticated_request do |access_token|
      service_class = "Quickbooks::Service::#{@entity}".constantize
      service = service_class.new( 
        company_id: @qbo.realm_id, 
        access_token: access_token 
      )
      if @remote.id.present?
        service.update(@remote.details)
      else
        service.create(@remote.details)
      end
    end

    @remote.id = remote.id unless @remote.persisted?
    log "Push for remote ##{@remote.id} completed."
    return @remote
  end

  private 

  # Log messages with the entity type for better traceability
  def log(msg)
    Rails.logger.info "[#{@entity}Service] #{msg}"
  end

end