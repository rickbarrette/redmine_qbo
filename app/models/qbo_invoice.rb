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
  
  has_and_belongs_to_many :issues, :association_foreign_key => 'qbo_invoice_id', :class_name => 'QboInvoice', :join_table => 'issues_qbo_invoices'
    
  attr_accessible :doc_number
  validates_presence_of :doc_number
  self.primary_key = :id
  
  def self.get_base
    Qbo.get_base(:invoice)
  end
  
  def self.sync
    #Pull the invoices from the quickbooks server
    #invoices = get_base.service.all
    
    last = Qbo.first.last_sync
    
    query = "SELECT Id, DocNumber FROM Invoice"
    query << " WHERE  Metadata.LastUpdatedTime >= '#{last.iso8601}' " if last
  
    if count == 0
      invoices = get_base.service.all 
    else
      invoices = get_base.service.query()
    end
    
    # Update the invoice table 
    invoices.each { | invoice | 
      qbo_invoice = find_or_create_by(id: invoice.id) 
      qbo_invoice.doc_number = invoice.doc_number 
      qbo_invoice.id = invoice.id
      qbo_invoice.save! 
    }
    
    #remove deleted invoices 
    #where.not(invoices.map(&:id)).destroy_all
  end
  
  def self.sync_by_id(id)
    #update the information in the database
    invoice = Qbo.get_base(:invoice).service.fetch_by_id(id) 
    qbo_invoice = find_or_create_by(id: invoice.id) 
    qbo_invoice.doc_number = invoice.doc_number 
    qbo_invoice.id = invoice.id
    qbo_invoice.save! 
    
    is_changed = false
    
    # Scan the line items for hashtags and attach to the applicable issues
    invoice.line_items.each { |line|
      if line.description
        line.description.scan(/#(\w+)/).flatten.each { |issue|
          i = Issue.find_by_id(issue.to_i)
          i.qbo_invoice << QboInvoice.find_by_id(invoice.id.to_i) if not i.qbo_invoice_ids.include?(invoice.id)
          i.save!
          
          # update the invoive custom fields with infomation from the work ticket if available
          invoice.custom_fields.each { |cf|
            # VIN
            if cf.name.eql? "VIN" and i.vehicles_id
              vin = Vehicle.find(i.vehicles_id).vin
              cf.string_value = vin if i.vehicles_id if not cf.string_value.to_s.eql? vin
              break
            end
            
            # Custom Values
            begin
              value = i.custom_values.find_by(custom_field_id: CustomField.find_by_name(cf.name).id)
              if value
                if not cf.string_value.to_s.eql? value.value.to_s and not value.value.to_s.blank?
                  cf.string_value = value.value.to_s
                  is_changed = true
                end
              end
            rescue
              # Nothing to do here, there is no match
            end
          }
          # Push updates
          Qbo.get_base(:invoice).service.update(invoice) if is_changed
        }
      end
    }
  end
  
  def self.update(id)
    # Update the item table
    invoice = get_base.service.fetch_by_id(id)
    qbo_invoice = find_or_create_by(id: id)
    qbo_invoice.doc_number = invoice.doc_number
    qbo_invoice.save!
  end
end
