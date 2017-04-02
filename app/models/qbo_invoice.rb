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
  belongs_to :customer 
  attr_accessible :doc_number, :id
  validates_presence_of :doc_number, :id
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
  
  private
  
   # Attach the invoice to the issue
  def self.attach_to_issue(issue, invoice)
    return if issue.nil?
    
    # skip this issue if the issue customer is not the same as the invoice customer
    return if issue.customer_id != invoice.customer_ref.value.to_i
    
    # Load the invoice into the database
    qbo_invoice = QboInvoice.find_or_create_by(id: invoice.id)
    qbo_invoice.doc_number = invoice.doc_number 
    qbo_invoice.id = invoice.id
    qbo_invoice.customer_id = invoice.customer_ref
    qbo_invoice.save!
    
    unless issue.qbo_invoices.include?(qbo_invoice)
      issue.qbo_invoices << qbo_invoice
      issue.save!
    end
    
    compare_custom_fields(issue, invoice)
  end
  
  # processes the invoice into the system
  def self.process_invoice(invoice)
    # Check the private notes 
    if not invoice.private_note.nil?
      invoice.private_note.scan(/#(\w+)/).flatten.each { |issue|
        attach_to_issue(Issue.find_by_id(issue.to_i), invoice)
      }
    end
    
    # Scan the line items for hashtags and attach to the applicable issues
    invoice.line_items.each { |line|
      if line.description
        line.description.scan(/#(\w+)/).flatten.each { |issue|
          attach_to_issue(Issue.find_by_id(issue.to_i), invoice)
        }
      end
    }
  end
  
  def self.compare_custom_fields(issue, invoice)
    is_changed = false
    
    # update the invoive custom fields with infomation from the work ticket if available
    invoice.custom_fields.each { |cf|
    
      # TODO Add some hooks here
      
      # VIN from the attached vehicle
      begin
        if cf.name.eql? "VIN"
          vin = Vehicle.find(issue.vehicles_id).vin
          break if vin.nil?
          if not cf.string_value.to_s.eql? vin
            cf.string_value = vin.to_s
            is_changed = true
          end
        end
      rescue
        #do nothing
      end
      
      # Custom Values
      begin
        value = issue.custom_values.find_by(custom_field_id: CustomField.find_by_name(cf.name).id)
        
        # Check to see if the value is blank...
        if not value.value.to_s.blank?
          # Check to see if the value is diffrent
          if not cf.string_value.to_s.eql? value.value.to_s
            
            # Use the lowest Milage
            if cf.name.eql? "Mileage In"
              if cf.string_value.to_i > value.value.to_i or cf.string_value.blank?
                cf.string_value = value.value.to_s
                is_changed = true
              end
            end
              
            # Use the max milage
            if cf.name.eql? "Mileage Out"
              if cf.string_value.to_i < value.value.to_i or cf.string_value.blank?
                cf.string_value = value.value.to_s
                is_changed = true
              end
            end
            
            # Everything else
            cf.string_value = value.value.to_s
            is_changed = true
          end
        end
      rescue
        # Nothing to do here, there is no match
      end
    }
    
    # TODO Add some hooks here

    # Push updates
    invoice.sync_token = invoice.sync_token +1 if is_changed
    get_base.update(invoice) if is_changed
  end
    
end
