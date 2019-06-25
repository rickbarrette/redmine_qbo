#The MIT License (MIT)
#
#Copyright (c) 2017 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class Customer < ActiveRecord::Base
  unloadable
  
  has_many :issues
  has_many :qbo_purchases
  has_many :qbo_invoices
  has_many :qbo_estimates
  has_many :vehicles
  
  attr_accessible :name, :notes, :email, :primary_phone, :mobile_phone, :phone_number
  validates_presence_of :id, :name
  
  self.primary_key = :id
  
  # returns a human readable string
  def to_s
    return name
  end
  
  # Convenience Method
  # returns the customer's email
  def email
    pull unless @details
    begin
      return @details.email_address.address
    rescue
      return nil
    end
  end
  
  # Convenience Method
  # Sets the email
  def email=(s)
    pull unless @details
    @details.email_address = s
  end
  
  # Convenience Method
  # returns the customer's primary phone
  def primary_phone
    pull unless @details
    begin
      return @details.primary_phone.free_form_number
    rescue
      return nil
    end
  end
  
  # Convenience Method
  # Updates the customer's primary phone number
  def primary_phone=(n)
    pull unless @details
    pn = Quickbooks::Model::TelephoneNumber.new
    pn.free_form_number = n
    @details.primary_phone = pn
    #update our locally stored number too
    update_phone_number
  end
  
  # Convenience Method
  # returns the customer's mobile phone
  def mobile_phone
    pull unless @details
    begin
      return @details.mobile_phone.free_form_number
    rescue
      return nil
    end
  end
  
  # Convenience Method
  # Updates the custome's mobile phone number
  def mobile_phone=(n)
    pull unless @details
    pn = Quickbooks::Model::TelephoneNumber.new
    pn.free_form_number = n
    @details.mobile_phone = pn
  end
  
  # update the localy stored phone number as a plain int
  def update_phone_number
    begin
      self.phone_number = self.primary_phone.tr('^0-9', '').to_i
    rescue
      return nil
    end
  end
  
  # Convenience Method
  # Updates Both local DB name & QBO display_name
  def name=(s)
    pull unless @details
    @details.display_name = s
    super
  end
  
  # Magic Method
  # Maps Get/Set methods to QBO customer object
  def method_missing(sym, *arguments)  
    # Check to see if the method exists
    if Quickbooks::Model::Customer.method_defined?(sym)
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
  
  # proforms a bruteforce sync operation
  # This needs to be simplified
  def self.sync 
    service = Qbo.get_base(:customer).service

    # Sync ALL customers if the database is empty
    #if count == 0
      customers = service.all
    #else
    #  last = Qbo.first.last_sync
    #  query = "Select Id, DisplayName From Customer"
    #  query << " Where Metadata.LastUpdatedTime >= '#{last.iso8601}' " if last
    #  customers = service.query(query)
    #end
    
    customers.each do |customer|
      qbo_customer = Customer.find_or_create_by(id: customer.id)
      if customer.active?
        if not qbo_customer.name.eql? customer.display_name
          qbo_customer.name = customer.display_name
          qbo_customer.id = customer.id
          qbo_customer.save_without_push
        end
      else
        if not qbo_customer.new_record?
          qbo_customer.delete
        end
      end
    end
  end
  
  # Searchs the database for a customer by name
  def self.search(search)
    customers = where("name LIKE ?", "%#{search}%")
    
    #if customers.empty?
    #  service = Qbo.get_base(:customer).service
    #  results = service.query("Select Id From Customer Where PrimaryPhone LIKE '%#{search}%' AND Mobile LIKE '%#{search}%'")
      
    #  results.each do |customer| 
    #    customers << Customer.find_by_id(customer.id)
    #  end
    #end
    
    return customers.order(:name)
  end
  
  # proforms a bruteforce sync operation
  # This needs to be simplified
  def self.sync_by_id(id) 
    service = Qbo.get_base(:customer).service

    customer = service.fetch_by_id(id)
    qbo_customer = Customer.find_or_create_by(id: customer.id)
    if customer.active?
      if not qbo_customer.name.eql? customer.display_name
        qbo_customer.name = customer.display_name
        qbo_customer.id = customer.id
        qbo_customer.save_without_push
      end
    else
      if not qbo_customer.new_record?
        qbo_customer.delete
      end
    end
  end
  
  # Push the updates
  def save_with_push
    begin
      @details = Qbo.get_base(:customer).service.update(@details)
      #raise "QBO Fault" if @details.fault?
      self.id = @details.id
    rescue Exception => e
      errors.add(e.message)
    end
    save_without_push
  end
  
  alias_method :save_without_push, :save
  alias_method :save, :save_with_push
  
  private
  
  # pull the details
  def pull
    begin
      raise Exception unless self.id
      @details = Qbo.get_base(:customer).find_by_id(self.id)
    rescue Exception => e
      @details = Quickbooks::Model::Customer.new
    end
  end
  
end
