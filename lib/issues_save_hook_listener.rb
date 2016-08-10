#The MIT License (MIT)
#
#Copyright (c) 2016 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class IssuesSaveHookListener < Redmine::Hook::ViewListener

  #Before Issue Saved
  def controller_issues_edit_before_save(context={})
    issue = context[:issue]

    # Check to see if we have registered with QBO
    if Qbo.first && issue.customer && issue.qbo_item
      
      # if this is a quote, lets create a new estimate based off estimated hours
        if issue.tracker.name = "Quote" && issue.status.name = "New" && issue.qbo_estimate
        
          # Get QBO Services
          item_service = QboItem.get_base.service
          estimate_base = QboEstimate.get_base
          
          # Create the estimate
          estimate  = estimate_base.qr_model(:estimate)
          estimate.customer_id = issue.customer_id
          estimate.txn_date = Date.today

          # Create the line item for labor
          item = item_service.fetch_by_id(issue.qbo_item_id)
          
          line_item = Quickbooks::Model::InvoiceLineItem.new
          line_item.amount = item.unit_price * issue.estimated_hours
          line_item.description = issue.subject
         
         line_item.sales_item! do |detail|
            detail.unit_price = item.unit_price
            detail.quantity = issue.estimated_hours
            detail.item_id =  issue.qbo_item_id
          end

          # Add the line items to the estimate
          estimate.line_items << line_item
        end
      end
  end

   # Called After Issue Saved
  def controller_issues_edit_after_save(context={})
    issue = context[:issue]
    
    if issue.assigned_to
      employee_id = issue.assigned_to.qbo_employee_id

      # Check to see if we have registered with QBO and if the issue is closed.
      # If so then we need to create a new billable time activity for the customer
      bill_time(issue, employee_id) if Qbo.first && issue.customer && issue.qbo_item && employee_id && issue.status.is_closed?
    end
  end
    
  # Create billable time entries
  def bill_time(issue, employee_id)
  
    # Get unbilled time entries
    spent_time = issue.time_entries.where(qbo_billed: [false, nil])
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
        item_id = Qbo.get_base(:item).service.query("SELECT Id FROM Item WHERE Name = '#{key}' ").first.id
        
        # Convert float spent time to hours and minutes
        hours = val.to_i
        minutesDecimal = (( spent_hours - hours) * 60)
        minutes = minutesDecimal.to_i
        
        item = item_service.fetch_by_id issue.qbo_item_id
        time_entry.description = "#{issue.tracker} ##{issue.id}: #{issue.subject}"
        # TODO entry.user.qbo_employee.id
        time_entry.employee_id = employee_id 
        time_entry.customer_id = issue.customer_id
        time_entry.billable_status = "Billable"
        time_entry.hours = hours
        time_entry.minutes = minutes
        time_entry.name_of = "Employee"
        time_entry.txn_date = Date.today
        time_entry.hourly_rate = item.unit_price
        time_entry.item_id = item_id #issue.qbo_item_id 
        time_entry.start_time = issue.start_date
        time_entry.end_time = Time.now
        time_service.create(time_entry)
      end
    end
  end
end
