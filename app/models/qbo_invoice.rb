#The MIT License (MIT)
#
#Copyright (c) 2016 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class QboInvoice < ActiveRecord::Base
  unloadable
  has_many :issues
  attr_accessible :doc_number
  validates_presence_of :id, :doc_number
  
  def self.get_base
    Qbo.get_base(:invoice)
  end
  
  def self.sync
    #Pull the invoices from the quickbooks server
    invoices = get_base.service.all
    
    # Update the invoice table 
    transaction do
      invoices.each { | invoice | 
        qbo_invoice = find_or_create_by(id: invoice.id) 
	qbo_invoice.doc_number = invoice.doc_number 
	qbo_invoice.id = invoice.id
	qbo_invoice.save! 
      }
    end 
    
    #remove deleted invoices 
    where.not(invoices.map(&:id)).destroy_all
  end
  
  def self.update(id)
    # Update the item table
    invoice = get_base.service.fetch_by_id(id)
      qbo_invoice = find_or_create_by(id: id)
      qbo_invoice.doc_number = invoice.doc_number
      qbo_invoice.save!
  end
end
