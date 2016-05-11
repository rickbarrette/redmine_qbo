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
  
  #before_save :qbo
  
  attr_accessible :name, :skip_details
  validates_presence_of :id, :name
  
  after_initialize :get_details, unless: :skip_details
  
  self.primary_key = :id
  
  # returns true if the customer is active
  def active?
    return @details.active? if @details
  end
  
  # returns a human readable string
  def to_s
    return name
  end
  
  # returns the customer's email
  def email
    begin
      return @details.email_address.address
    rescue
      return nil
    end
  end
  
  # returns the customer's primary phone
  def primary_phone
    begin
      return @details.primary_phone.free_form_number
    rescue
      return nil
    end
  end
  
  # Updates the customer's primary phone number
  def primary_phone=(n)
    Quickbooks::Model::TelephoneNumber.new
    pn.free_form_number = n
    @details.primary_phone = pn
    push
  end
  
  # returns the customer's mobile phone
  def mobile_phone
    begin
      return @details.mobile_phone.free_form_number
    rescue
      return nil
    end
  end
  
  # Updates the custome's mobile phone number
  def mobile_phone=(n)
    Quickbooks::Model::TelephoneNumber.new
    pn.free_form_number = n
    @details.mobile_phone = pn
    push
  end
  
  # returns the customer's notes
  def notes
    return @details.notes if @details
  end
  
  # updates the customer's notes in QBO
  def notes=(s)
    @details.notes = s if @details
    push
  end
  
  # returns the bases QBO service for customers
  def self.get_base
    Qbo.get_base(:customer)
  end
  
  # returns the QBO customer 
  def get_customer (id)
    begin
      return get_base.find_by_id(id)
    rescue
      return nil
    end
  end

  # proforms a bruteforce sync operation
  # This needs to be simplified
  def self.sync 
    last = Qbo.first.last_sync
    
    query = "SELECT Id, DisplayName FROM Customer"
    query << " WHERE Metadata.LastUpdatedTime>'#{last}' " if last
    
    customers = get_base.service.query()

    transaction do
      # Update the customer table
      customers.each { |customer|
        qbo_customer = Customer.find_or_create_by(id: customer.id)
        # only update if diffrent
        if qbo_customer.new_record?
          qbo_customer.name = customer.display_name
          qbo_customer.id = customer.id
          qbo_customer.save!
        end
      }
    end
   
    # remove deleted customers
    #where.not(customers.map(&:id)).destroy_all
  end
  
  # Magic Method
  def method_missing(name, *arguments)
    value = arguments[0]
    name = name.to_s

    # if the method's name ends with '='
    if name[-1, 1] == "="
      method_name = name[0..-2]
      @details[method_name] = value
      push
    else
      begin
        return @details[name]
      rescue
        return nil
      end
    end
  end
  
  private
  
  # Push the updates
  def push
    begin 
      get_base.update(@details)
    rescue
      return nil
    end
  end
  
  def qbo
    if new_record?
      customer = Quickbooks::Model::Customer.new
      customer.display_name = self.name
      @details = Qbo.get_base(:customer).service.create(customer)
      self.id = @details.id
    end
  end
  
  # init details
  def get_details
    if self.id
      @details = get_customer(self.id)
    end
  end
  
  # update's the customers name if updated
  def update
    begin
      if not self.name == @detils.display_name
        self.name = @details.display_name
        self.save
      end
    rescue
      return nil
    end
  end
  
end
