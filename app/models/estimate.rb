#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class Estimate < ActiveRecord::Base
  
  has_and_belongs_to_many :issues
  belongs_to :customer 
  validates_presence_of :doc_number, :id
  self.primary_key = :id

  # returns a human readable string
  def to_s
    return self[:doc_number]
  end
  
  # sync all estimates
  def self.sync
    EstimateSyncJob.perform_later(full_sync: false)
  end
  
  # sync only one estimate
  def self.sync_by_id(id)
    EstimateSyncJob.perform_later(id: id)
  end

  # sync only one estimate
  def self.sync_by_doc_number(number)
    EstimateSyncJob.perform_later(doc_number: number)
  end

  # download the pdf from quickbooks
  def pdf
    log "Downloading PDF for estimate ##{self.id}..."
    qbo = Qbo.first
    qbo.perform_authenticated_request do |access_token|
      service = Quickbooks::Service::Estimate.new(company_id: qbo.realm_id, access_token: access_token)
      estimate = service.fetch_by_id(id)
      service.pdf(estimate)
    end
  end

  # Magic Method
  # Maps Get/Set methods to QBO estimate object
  def method_missing(sym, *arguments)
    # Check to see if the method exists
    if Quickbooks::Model::Estimate.method_defined?(sym)
      # download details if required
      pull unless @details
      method_name = sym.to_s
      # Setter
      if method_name[-1, 1] == "="
        @details.method(method_name).call(arguments[0])
      # Getter
      else
        return @details.method(method_name).call 
      end
    end
  end

  private
  
  # pull the details
  def pull
    log "Pulling details for estimate ##{self.id}..."
    begin
      raise Exception unless self.id
      qbo = Qbo.first
      @details = qbo.perform_authenticated_request do |access_token|
        service = Quickbooks::Service::Estimate.new(company_id: qbo.realm_id, access_token: access_token)
        service(:estimate).fetch_by_id(self.id)
      end
    rescue Exception => e
      @details = Quickbooks::Model::Estimate.new
    end
  end

  def log(msg)
    Rails.logger.info "[Estimate] #{msg}"
  end
  
end
