#The MIT License (MIT)
#
#Copyright (c) 2016 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class QboCustomer < ActiveRecord::Base
  unloadable
  has_many :issues
  has_many :qbo_purchases
  has_many :vehicles
  attr_accessible :name
  validates_presence_of :id, :name
  
  def to_s; name end
  
   def get_base
    Qbo.get_base(:customer)
  end
   
  def get_customer (id)
    get_base.service.find_by_id(id)
  end

  def update_all 
    customers = get_base.service.all

    transaction do
      # Update the customer table
      customers.each { |customer|
        qbo_customer = QboCustomer.find_or_create_by(id: customer.id)
        qbo_customer.name = customer.display_name
        qbo_customer.id = customer.id
        qbo_customer.save!
      }
    end
   
    #remove deleted customers
    where.not(customers.map(&:id)).destroy_all
  end
end
