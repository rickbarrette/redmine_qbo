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
  attr_accessible :name
  validates_presence_of :id, :name
  
   def self.get_base
    Quickbooks::Base.new(Qbo.get_account, :employee)
  end
   
  def self.get_customer (id)
    get_base.service.find_by_id(id)
  end

  def self.update_all 
    # Update the customer table
    get_base.service.all.each { |customer|
      qbo_customer = QboCustomer.find_or_create_by(id: customer.id)
      qbo_customer.id = customer.id
      qbo_customer.name = customer.display_name
      qbo_customer.save!
    }
  end
end
