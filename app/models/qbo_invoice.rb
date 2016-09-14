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
  
  has_and_belongs_to_many :issues
  attr_accessible :doc_number
  validates_presence_of :doc_number
  self.primary_key = :id
  
  def self.get_base
    Qbo.get_base(:invoice).service
  end
  
  # sync ALL the invoices
  def self.sync
    last = Qbo.first.last_sync
    
    query = "SELECT Id, DocNumber FROM Invoice"
    query << " WHERE  Metadata.LastUpdatedTime >= '#{last.iso8601}' " if last
  
    if count == 0
      invoices = get_base.all 
    else
      invoices = get_base.query()
    end
    
    # Update the invoice table 
    invoices.each { | invoice | 
      process_invoice invoice
    }
  end
  
  #sync by invoice ID
  def self.sync_by_id(id)
    #update the information in the database
    invoice = get_base.fetch_by_id(id) 
    process_invoice invoice
  end
  
  # processes the invoice into the system
  def self.process_invoice(invoice)
    
    
    
    is_changed = false
    
    # Scan the line items for hashtags and attach to the applicable issues
    invoice.line_items.each { |line|
      if line.description
        line.description.scan(/#(\w+)/).flatten.each { |issue|
          i = Issue.find_by_id(issue.to_i)
          begin
            # Load the invoice into the database
            qbo_invoice = QboInvoice.find_or_create_by(id: invoice.id)
            #if qbo_invoice.new?
              qbo_invoice.doc_number = invoice.doc_number 
              qbo_invoice.id = invoice.id
              qbo_invoice.save!
            #end

            # Attach the invoice to the issue
            unless i.qbo_invoices.include?(qbo_invoice)
              i.qbo_invoices << qbo_invoice.id
              i.qbo_invoices.save!
            end
          rescue
            puts "Something when wrong..."
            # do nothing, the reccord exists
          end
          
          # update the invoive custom fields with infomation from the work ticket if available
          invoice.custom_fields.each { |cf|
            # VIN
            begin
              if cf.name.eql? "VIN"
                vin = Vehicle.find(i.vehicles_id).vin
                break if vin.blank?
                if not cf.string_value.to_s.eql? vin
                  cf.string_value = vin
                  is_changed = true
                  break
                end
              end
            rescue
              #do nothing
            end
            
            # Custom Values
            begin
              value = i.custom_values.find_by(custom_field_id: CustomField.find_by_name(cf.name).id)
              if not value.value.to_s.blank?
                if not cf.string_value.to_s.eql? value.value.to_s
                  cf.string_value = value.value.to_s
                  is_changed = true
                end
              end
            rescue
              # Nothing to do here, there is no match
            end
          }
          
        }
      end
    }
    
    # Push updates
    get_base.update(invoice) if is_changed
  end
  
end
