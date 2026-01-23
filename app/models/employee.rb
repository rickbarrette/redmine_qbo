#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class Employee < ActiveRecord::Base
  
  has_many :users
  validates_presence_of :id, :name
  
  def self.sync 
    qbo = Qbo.first
    employees = qbo.perform_authenticated_request do |access_token|
      service = Quickbooks::Service::Employee.new(:company_id => qbo.realm_id, :access_token => access_token)
      service.all
    end

    return unless employees
    
    transaction do
      # Update the item table
      employees.each { |e|
        logger.info "Processing employee #{e.id}"
        employee = 	find_or_create_by(id: e.id)
        employee.name = e.display_name
        employee.id = e.id
        employee.save!
      }
    end
  end

  def self.sync_by_id(id)
    qbo = Qbo.first
    employee = qbo.perform_authenticated_request do |access_token|
      service = Quickbooks::Service::Employee.new(:company_id => qbo.realm_id, :access_token => access_token)
      service.fetch_by_id(id)
    end

    return unless employee
    employee = find_or_create_by(id: employee.id)
    employee.name = employee.display_name
    employee.id = employee.id
    employee.save!
  end
end
