#The MIT License (MIT)
#
#Copyright (c) 2016 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require_dependency 'issue'

# Patches Redmine's Issues dynamically.  
# Adds a relationships
module IssuePatch

  def self.included(base) # :nodoc:
    base.extend(ClassMethods)

    base.send(:include, InstanceMethods)

    # Same as typing in the class 
    base.class_eval do
      unloadable # Send unloadable so it will not be unloaded in development
      belongs_to :customer, primary_key: :id
      belongs_to :customer_token, primary_key: :id
      belongs_to :qbo_estimate, primary_key: :id
      has_and_belongs_to_many :qbo_invoices
        #, :association_foreign_key => 'issue_id', :class_name => 'Issue', :join_table => 'issues_qbo_invoices'
  
      belongs_to :vehicle, primary_key: :id
    end
    
  end
    
  module ClassMethods
    
  end
  
  module InstanceMethods
    
    # Create billable time entries
    def bill_time
      
      # Get unbilled time entries
      spent_time = time_entries.where(qbo_billed: [false, nil])
      spent_hours ||= spent_time.sum(:hours) || 0
      
      if spent_hours > 0 then
      
        # Prepare to create a new Time Activity
        time_service = Qbo.get_base(:time_activity).service
        item_service = Qbo.get_base(:item).service
        time_entry = Quickbooks::Model::TimeActivity.new
  
        h = Hash.new(0)
        spent_time.each do |entry|
          # Lets tottal up each activity
          h[entry.activity.name] += entry.hours
          # update time entries billed status
          entry.qbo_billed = true
          entry.save
        end
        
        h.each do |key, val|
          
          # Convert float spent time to hours and minutes
          hours = val.to_i
          minutesDecimal = (( val - hours) * 60)
          minutes = minutesDecimal.to_i
          
          item = item_service.query("SELECT * FROM Item WHERE Name = '#{key}' ").first
          next if item.nil?
          
          time_entry.description = "#{tracker} ##{id}: #{subject} #{"(Partial)" if not closed?}"
          # TODO entry.user.qbo_employee.id
          time_entry.employee_id = assigned_to.qbo_employee_id 
          time_entry.customer_id = customer_id
          time_entry.billable_status = "Billable"
          time_entry.hours = hours
          time_entry.minutes = minutes
          time_entry.name_of = "Employee"
          time_entry.txn_date = Date.today
          time_entry.hourly_rate = item.unit_price
          time_entry.item_id = item.id 
          time_entry.start_time = start_date
          time_entry.end_time = Time.now
          time_service.create(time_entry)
        end
      end
    end
  end
  
  # Create a shareable link for a customer
  def share_link
    token = CustomerToken.create(:expires_at => Time.now + 24.hours, :issue_id => id)
    link_to "#{tracker} ##{id}: #{subject}", view_path + token.token 
  end
  
end    

# Add module to Issue
Issue.send(:include, IssuePatch)
