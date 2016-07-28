#The MIT License (MIT)
#
#Copyright (c) 2016 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class QboEmployee < ActiveRecord::Base
  unloadable
  has_many :users
  attr_accessible :name
  validates_presence_of :id, :name
  
  def self.get_base
    Qbo.get_base(:employee)
  end
  
  def self.sync 
    employees = get_base.service.all
    
    transaction do
      # Update the item table
      employees.each { |employee|
        qbo_employee = 	find_or_create_by(id: employee.id)
        qbo_employee.name = employee.display_name
        qbo_employee.id = employee.id
        qbo_employee.save!
      }
    end
    
  def self.sync_by_id(id)
    employee = get_base.service.fetch_by_id(id)
    
    qbo_employee = 	find_or_create_by(id: employee.id)
    qbo_employee.name = employee.display_name
    qbo_employee.id = employee.id
    qbo_employee.save!
  end
end
