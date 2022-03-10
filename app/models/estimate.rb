#The MIT License (MIT)
#
#Copyright (c) 2022 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class Estimate < ActiveRecord::Base
  unloadable
  
  has_and_belongs_to_many :issues
  belongs_to :customer 
  #attr_accessible :doc_number, :id
  validates_presence_of :doc_number, :id
  self.primary_key = :id
  
  # return the QBO Estimate service
  def self.get_base
    Qbo.get_base(:estimate)
  end
  
  # sync all estimates
  def self.sync
    logger.debug "Syncing ALL estimates"
    estimates = get_base.all
    estimates.each { |estimate|
      process_estimate(estimate)
    }

    #remove deleted estimates
    where.not(estimates.map(&:id)).destroy_all
  end
  
  # sync only one estimate
  def self.sync_by_id(id)
    logger.debug "Syncing estimate #{id}"
    process_estimate(get_base.fetch_by_id(id))
  end
  
  # update an estimate
  def self.update(id)
    # Update the item table
    estimate = get_base.fetch_by_id(id)
    estimate = find_or_create_by(id: id)
    estimate.doc_number = estimate.doc_number
    estimate.txn_date = estimate.txn_date
    estimate.save!
  end
  
  # process an estimate into the database
  def self.process_estimate(estimate)
    logger.info "Processing estimate #{estimate.id}"
    estimate = find_or_create_by(id: estimate.id)
    estimate.doc_number = estimate.doc_number
    estimate.customer_id = estimate.customer_ref.value
    estimate.id = estimate.id
    estimate.txn_date = estimate.txn_date
    estimate.save!
  end

  # download the pdf from quickbooks
  def pdf
    base = Estimate.get_base
    estimate = base.fetch_by_id(id)
    return base.pdf(estimate)
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
      @details = Qbo.get_base(:estimate).fetch_by_id(self.id)
    rescue Exception => e
      @details = Quickbooks::Model::Estimate.new
    end
  end
  
end
