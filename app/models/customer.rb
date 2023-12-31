#The MIT License (MIT)
#
#Copyright (c) 2023 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class Customer < ActiveRecord::Base
  unloadable
  
  has_many :issues
  has_many :purchases
  has_many :invoices
  has_many :estimates
  has_many :vehicles
  
  validates_presence_of :id, :name
  
  self.primary_key = :id
  
  # returns a human readable string
  def to_s
    return "#{self[:name]} - #{phone_number.split(//).last(4).join unless phone_number.nil?}"
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
    #update our locally stored number too
    update_mobile_phone_number
  end

  # Convenience Method
  # Sets the notes
  def notes=(s)
    pull unless @details
    @details.notes = s
  end
  
  # update the localy stored phone number as a plain string with no special chars
  def update_phone_number
    begin
      self.phone_number = self.primary_phone.tr('^0-9', '')
    rescue
      return nil
    end
  end
  
  # update the localy stored phone number as a plain string with no special chars
  def update_mobile_phone_number
    begin
      self.mobile_phone_number = self.mobile_phone.tr('^0-9', '')
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
    # Sync ALL customers if the database is empty
    qbo = Qbo.first
    qbo.perform_authenticated_request do |access_token|
      service = Quickbooks::Service::Customer.new(:company_id => qbo.realm_id, :access_token => access_token)
      customers = service.all
    end
    
    return unless customers
    
    customers.each do |c|
      logger.info "Processing customer #{c.id}"
      customer = Customer.find_or_create_by(id: c.id)
      if c.active?
        if not customer.name.eql? c.display_name
          customer.name = c.display_name
          customer.id = c.id
          customer.save_without_push
        end
      else
        if not c.new_record?
          customer.delete
        end
      end
    end
  end
  
  # Searchs the database for a customer by name or phone number with out special chars
  def self.search(search)
    customers = where("name LIKE ? OR phone_number LIKE ? OR mobile_phone_number LIKE ?", "%#{search}%", "%#{search}%", "%#{search}%")
    return customers.order(:name)
  end
  
  # proforms a bruteforce sync operation
  # This needs to be simplified
  def self.sync_by_id(id) 
    qbo = Qbo.first
    qbo.perform_authenticated_request do |access_token|
      service = Quickbooks::Service::Customer.new(:company_id => qbo.realm_id, :access_token => access_token)
      customer = service.fetch_by_id(id)
    end

    return unless customer

    customer = Customer.find_or_create_by(id: customer.id)
    if customer.active?
      if not customer.name.eql? customer.display_name
        customer.name = customer.display_name
        customer.id = customer.id
        customer.save_without_push
      end
    else
      if not customer.new_record?
        customer.delete
      end
    end
  end
  
  # Push the updates
  def save_with_push
    begin
      qbo = Qbo.first
      qbo.perform_authenticated_request do |access_token|
        service = Quickbooks::Service::Customer.new(:company_id => qbo.realm_id, :access_token => access_token)
        @details = serivce.update(@details)
      end
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
      qbo = Qbo.first
      qbo.perform_authenticated_request do |access_token|
        service = Quickbooks::Service::Customer.new(:company_id => qbo.realm_id, :access_token => access_token)
        @details = bservice.ase.fetch_by_id(self.id)
      end
    rescue Exception => e
      @details = Quickbooks::Model::Customer.new
    end
  end
  
end
