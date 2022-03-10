#The MIT License (MIT)
#
#Copyright (c) 2022 rick barrette
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
      belongs_to :estimate, primary_key: :id
      has_and_belongs_to_many :invoices
      belongs_to :vehicle, primary_key: :id
    end
    
  end
    
  module ClassMethods
    
  end
  
  module InstanceMethods
    
    # Create billable time entries
    def bill_time
     
      # Check to see if we have everything we need to bill the customer
      return if assigned_to.nil?
      return unless Qbo.first 
      return unless customer 

      # Get unbilled time entries
      spent_time = time_entries.where(billed: [false, nil])
      spent_hours ||= spent_time.sum(:hours) || 0
      
      if spent_hours > 0 then
        
        # Prepare to create a new Time Activity
        time_service = Qbo.get_base(:time_activity)
        item_service = Qbo.get_base(:item)
        time_entry = Quickbooks::Model::TimeActivity.new
  
        # Lets total up each activity before billing.
        # This will simpify the invoicing with a single billable time entry per time activity
        h = Hash.new(0)
        spent_time.each do |entry|
          h[entry.activity.name] += entry.hours
          # update time entries billed status
          entry.billed = true
          entry.save
        end
        
        # Now letes upload our totals for each activity as their own billable time entry
        h.each do |key, val|
          
          # Convert float spent time to hours and minutes
          hours = val.to_i
          minutesDecimal = (( val - hours) * 60)
          minutes = minutesDecimal.to_i

          # Lets match the activity to an qbo item
          item = item_service.query("SELECT * FROM Item WHERE Name = '#{key}' ").first
          next if item.nil?
          
          # Create the new billable time entry and upload it
          time_entry.description = "#{tracker} ##{id}: #{subject} #{"(Partial @ #{done_ratio}%)" if not closed?}"
          time_entry.employee_id = assigned_to.employee_id 
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
  def share_token
    CustomerToken.create(:expires_at => Time.now + 1.month, :issue_id => id)
  end
  
end  

# Add module to Issue
Issue.send(:include, IssuePatch)
