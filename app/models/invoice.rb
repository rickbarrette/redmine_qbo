#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class Invoice < ActiveRecord::Base
  
  has_and_belongs_to_many :issues
  belongs_to :customer 
  validates_presence_of :doc_number, :id, :customer_id, :txn_date
  self.primary_key = :id
  
  # sync ALL the invoices
  def self.sync
    logger.info "Syncing all invoices"
    last = Qbo.first.last_sync

    query = "SELECT Id, DocNumber FROM Invoice"
    query << " WHERE Metadata.LastUpdatedTime >= '#{last.iso8601}' " if last
  
    # TODO actually do something with the above query
    # .all() is never called since count is never initialized
    qbo = Qbo.first
    invoices = qbo.perform_authenticated_request do |access_token|
      service = Quickbooks::Service::Invoice.new(:company_id => qbo.realm_id, :access_token => access_token)
      service.all 
    end

    return unless invoices
     
    invoices.each { | invoice | 
      process_invoice invoice
    }
  end
  
  #sync by invoice ID
  def self.sync_by_id(id)
    logger.info "Syncing invoice #{id}"
    qbo = Qbo.first
    qbo.perform_authenticated_request do |access_token|
      service = Quickbooks::Service::Invoice.new(:company_id => qbo.realm_id, :access_token => access_token)
      invoice = service.fetch_by_id(id) 
      process_invoice invoice
    end
  end
  
  private
  
  # Attach the invoice to the issue
  def self.attach_to_issue(issue, invoice)
    return if issue.nil?
    
    # skip this issue if the issue customer is not the same as the invoice customer
    return if issue.customer_id != invoice.customer_ref.value.to_i
    
    logger.info "Attaching invoice #{invoice.id} to issue #{issue.id}"
    
    invoice = Invoice.find_or_create_by(id: invoice.id)

    unless issue.invoices.include?(invoice)
      issue.invoices << invoice
      issue.save!
    end
    
    compare_custom_fields(issue, invoice)
  end
  
  # processes the invoice into the database
  def self.process_invoice(i)
    logger.info "Processing invoice #{i.id}"

    # Load the invoice into the database
    invoice = Invoice.find_or_create_by(id: i.id)
    invoice.doc_number = i.doc_number 
    invoice.id = i.id
    invoice.customer_id = i.customer_ref
    invoice.txn_date = i.txn_date
    invoice.save!

    # Scan the private notes for hashtags and attach to the applicable issues
    if not i.private_note.nil?
      i.private_note.scan(/#(\w+)/).flatten.each { |issue|
        attach_to_issue(Issue.find_by_id(issue.to_i), invoice)
      }
    end
    
    # Scan the line items for hashtags and attach to the applicable issues
    i.line_items.each { |line|
      if line.description
        line.description.scan(/#(\w+)/).flatten.each { |issue|
          attach_to_issue(Issue.find_by_id(issue.to_i), invoice)
        }
      end
    }
  end
  
  # compares the custome fields on invoices & issues and updates the invoice as needed
  #
  # the issue here is when two or more issues share an invoice with the same custom field, but diffrent values
  # this condions causes an infinite loop as the webhook is called when an invoice is updated
  # TODO maybe add a cf_sync_confict flag to invoices
  def self.compare_custom_fields(issue, invoice)
    logger.info "Comparing custom fields"
    # TODO break if Invoice.find(invoice.id).cf_sync_confict
    is_changed = false

    logger.debug "Calling :process_invoice_custom_fields hook"
    context = Redmine::Hook.call_hook :process_invoice_custom_fields, { issue: issue, invoice: invoice } 

    unless context.nil?
      logger.debug "We have a context!"
      context= context.first
      issue = context[:issue]
      invoice = context[:invoice]
      is_changed = context[:is_changed]
    end
      
    # Custom Values
    begin
      value = issue.custom_values.find_by(custom_field_id: CustomField.find_by_name(cf.name).id)
      
      # Check to see if the value is blank...
      if not value.value.to_s.blank?
        # Check to see if the value is diffrent
        if not cf.string_value.to_s.eql? value.value.to_s
          # update the custom field on the invoice
          cf.string_value = value.value.to_s
          is_changed = true
        end
      end
    rescue
      # Nothing to do here, there is no match
    end

    # Push updates
    begin
      logger.info "Trying to update invoice"
      qbo = Qbo.first
      qbo.perform_authenticated_request do |access_token|
        service = Quickbooks::Service::Invoice.new(:company_id => qbo.realm_id, :access_token => access_token)
        service.update(invoice) if is_changed
      end
    rescue
      # Do nothing, probaly custome field sync confict on the invoice. 
      # This is a problem with how it's billed
      # TODO Add notes in memo area
      # TODO flag Invoice.cf_sync_confict here
      logger.error "Failed to update invoice"
    end
  end

  # download the pdf from quickbooks
  def pdf
    qbo = Qbo.first
    qbo.perform_authenticated_request do |access_token|
      service = Quickbooks::Service::Invoice.new(:company_id => qbo.realm_id, :access_token => access_token)
      invoice = service.fetch_by_id(id)
      return service.pdf(invoice)
    end
  end

  # Magic Method
  # Maps Get/Set methods to QBO invoice object
  def method_missing(sym, *arguments)
    # Check to see if the method exists
    if Quickbooks::Model::Invoice.method_defined?(sym)
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
  
  # pull the details from quickbooks
  def pull
    begin
      raise Exception unless self.id
      qbo = Qbo.first
      @details = qbo.perform_authenticated_request do |access_token|
        service = Quickbooks::Service::Invoice.new(:company_id => qbo.realm_id, :access_token => access_token)
        service.fetch_by_id(self.id)
      end
    rescue Exception => e
      @details = Quickbooks::Model::Invoice.new
    end
  end
    
end
