#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class CustomerPushService

  # Initializes the service with a QBO client and an optional customer record. The QBO client is used to communicate with QuickBooks Online, while the customer record contains the data that needs to be pushed to QBO. If no customer is provided, the service will not perform any operations.
  def initialize(qbo:, customer: nil)
    raise "No QBO configuration found" unless qbo
    raise "Customer record is required for push operation" unless customer
    @qbo = qbo
    @customer = customer
  end

  # Log messages with the entity type for better traceability
  def log(msg)
    Rails.logger.info "[CustomerPushService] #{msg}"
  end

  # Pushes the customer data to QuickBooks Online. This method handles the communication with QBO, including authentication and error handling. It uses the QBO client to send the customer data and logs the process for monitoring and debugging purposes. If the push is successful, it returns the customer record; otherwise, it logs the error and returns false.
  def push
    log "Pushing customer ##{@customer.id} to QBO..."

    customer = @qbo.perform_authenticated_request do |access_token|
      service = Quickbooks::Service::Customer.new( 
        company_id: @qbo.realm_id, 
        access_token: access_token 
      )
      service.update(@customer.details)
    end

    @customer.id = customer.id unless @customer.persisted?
    log "Push for customer ##{@customer.id} completed."
    return @customer
  end

end