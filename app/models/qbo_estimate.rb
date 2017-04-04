#The MIT License (MIT)
#
#Copyright (c) 2017 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class QboEstimate < ActiveRecord::Base
  unloadable
  
  has_and_belongs_to_many :issues
  belongs_to :customer 
  attr_accessible :doc_number, :id
  validates_presence_of :doc_number, :id
  self.primary_key = :id
  
  # return the QBO Estimate service
  def self.get_base
    Qbo.get_base(:estimate).service
  end
  
  # sync all estimates
  def self.sync 
    estimates = get_base.all
    estimates.each { |estimate|
      process_estimate(estimate)
    }

    #remove deleted estimates
    where.not(estimates.map(&:id)).destroy_all
  end
  
  # sync only one estimate
  def self.sync_by_id(id)
    process_estimate(get_base.fetch_by_id(id))
  end
  
  # update an estimate
  def self.update(id)
    # Update the item table
    estimate = get_base.fetch_by_id(id)
    qbo_estimate = find_or_create_by(id: id)
    qbo_estimate.doc_number = estimate.doc_number
    qbo_estimate.save!
  end
  
  # process an estimate into the database
  def self.process_estimate(estimate)
    qbo_estimate = find_or_create_by(id: estimate.id)
    qbo_estimate.doc_number = estimate.doc_number
    qbo_estimate.customer_id = estimate.customer_ref.value
    qbo_estimate.id = estimate.id
    qbo_estimate.save!
  end
end
