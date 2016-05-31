#The MIT License (MIT)
#
#Copyright (c) 2016 rick barrette
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
  has_many :vehicles
  
  attr_accessible :name 
  
  validates_presence_of :id, :name
  
  self.primary_key = :id
  
  # returns a human readable string
  def to_s
    return name
  end
  
  # returns the customer's email
  def email
    pull unless @details
    begin
      return @details.email_address.address
    rescue
      return nil
    end
  end
  
  # returns the customer's primary phone
  def primary_phone
    pull unless @details
    begin
      return @details.primary_phone.free_form_number
    rescue
      return nil
    end
  end
  
  # Updates the customer's primary phone number
  def primary_phone=(n)
    pull unless @details
    pn = Quickbooks::Model::TelephoneNumber.new
    pn.free_form_number = n
    @details.primary_phone = pn
  end
  
  # returns the customer's mobile phone
  def mobile_phone
    pull unless @details
    begin
      return @details.mobile_phone.free_form_number
    rescue
      return nil
    end
  end
  
  # Updates the custome's mobile phone number
  def mobile_phone=(n)
    pull unless @details
    pn = Quickbooks::Model::TelephoneNumber.new
    pn.free_form_number = n
    @details.mobile_phone = pn
  end
  
  # Updates Both local DB name & QBO display_name
  def name=(s)
    pull unless @details
    @details.display_name = s
    super
  end
  
  # Magic Method  
  def method_missing(n, *arguments)  
    pull unless @details
    value = arguments[0]  
    method_name = n.to_s
    # Check to see if the method exists
    if @details.instance_methods(true).include?(n) 
      if method_name[-1, 1] == "="  
        @details.method(method_name).call(value)  
      else  
        return @details.method(method_name).call 
      end
    else
      super
    end  
  end  
  
  # proforms a bruteforce sync operation
  # This needs to be simplified
  def self.sync 
    last = Qbo.first.last_sync
    service =  Qbo.get_base(:customer).service

    query = "Select Id, DisplayName From Customer"
    query << " Where Metadata.LastUpdatedTime >= '#{last.iso8601}' " if last
    
    if count == 0
      customers = service.all
    else
      customers = service.query(query)
    end
    
    customers.each do |customer|
      qbo_customer = Customer.find_or_create_by(id: customer.id)
      qbo_customer.name = customer.display_name
      qbo_customer.id = customer.id
      qbo_customer.save_without_push
    end
  
    # remove deleted customers
    #where.not(customers.map(&:id)).destroy_all
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
      #tries ||= 3
      raise Exception unless self.id
      @details = Qbo.get_base(:customer).find_by_id(self.id)
    rescue Exception => e
      #retry unless (tries -= 1).zero?
      @details = Quickbooks::Model::Customer.new
    end
  end
  
end
