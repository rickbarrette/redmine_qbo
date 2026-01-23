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
  
  # sync all estimates
  def self.sync
    logger.info "Syncing ALL estimates"
    qbo = Qbo.first
    estimates = qbo.perform_authenticated_request do |access_token|
      service = Quickbooks::Service::Estimate.new(:company_id => qbo.realm_id, :access_token => access_token)
      service.all
    end

    return unless estimates

    estimates.each { |estimate|
      process_estimate(estimate)
    }

    #remove deleted estimates
    where.not(estimates.map(&:id)).destroy_all
  end
  
  # sync only one estimate
  def self.sync_by_id(id)
    logger.info "Syncing estimate #{id}"
    qbo = Qbo.first
    qbo.perform_authenticated_request do |access_token|
      service = Quickbooks::Service::Estimate.new(:company_id => qbo.realm_id, :access_token => access_token)
      process_estimate(service.fetch_by_id(id))
    end
  end

  # sync only one estimate
  def self.sync_by_doc_number(number)
    logger.info "Syncing estimate by doc number #{number}"
    qbo = Qbo.first
    qbo.perform_authenticated_request do |access_token|
      service = Quickbooks::Service::Estimate.new(:company_id => qbo.realm_id, :access_token => access_token)
      process_estimate(service.find_by( :doc_number, number).first)
    end
  end
  
  # update an estimate
  def self.update(id)
    # Update the item table
    qbo = Qbo.first
    estimate = qbo.perform_authenticated_request do |access_token|
      service = Quickbooks::Service::Estimate.new(:company_id => qbo.realm_id, :access_token => access_token)
      service.fetch_by_id(id)
    end

    return unless estimate

    e = find_or_create_by(id: id)
    e.doc_number = estimate.doc_number
    e.txn_date = estimate.txn_date
    e.save!
  end
  
  # process an estimate into the database
  def self.process_estimate(qbo_estimate)
    logger.info "Processing estimate #{qbo_estimate.id}"
    estimate = find_or_create_by(id: qbo_estimate.id)
    estimate.doc_number = qbo_estimate.doc_number
    estimate.customer_id = qbo_estimate.customer_ref.value
    estimate.id = qbo_estimate.id
    estimate.txn_date = qbo_estimate.txn_date
    estimate.save!
  end

  # download the pdf from quickbooks
  def pdf
    qbo = Qbo.first
    qbo.perform_authenticated_request do |access_token|
      service = Quickbooks::Service::Estimate.new(:company_id => qbo.realm_id, :access_token => access_token)
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
    begin
      raise Exception unless self.id
      qbo = Qbo.first
      @details = qbo.perform_authenticated_request do |access_token|
        service = Quickbooks::Service::Estimate.new(:company_id => qbo.realm_id, :access_token => access_token)
        service(:estimate).fetch_by_id(self.id)
      end
    rescue Exception => e
      @details = Quickbooks::Model::Estimate.new
    end
  end
  
end
