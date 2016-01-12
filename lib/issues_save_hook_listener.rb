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
    cf_estimate = CustomField.find_by_name("Estimate")
    
    # Check to see if we have registered with QBO
    unless Qbo.first.nil? and issue.qbo_customer_id.nil? and issue.qbo_item_id.nil? and employee_id.nil? then
     
      # if this is a quote, lets create a new estimate based off estimated hours
        if issue.tracker.name = "Quote" and issue.status.name = "New" and cf_estimate.nil? then
        
          item_service = Quickbooks::Service::Item.new(:company_id => Qbo.get_realm_id, :access_token => Qbo.get_auth_token)
          
          estimate  = Quickbooks::Model::Estimate .new
          estimate .customer_id = issue.qbo_customer_id
          estimate .txn_date = Date.today

          item = item_service.fetch_by_id issue.qbo_item_id
          line_item = Quickbooks::Model::InvoiceLineItem.new
          line_item.amount = item.unit_price * issue.estimated_hours
          line_item.description = issue.subject
         
         line_item.sales_item! do |detail|
            detail.unit_price = item.unit_price
            detail.quantity = issue.estimated_hours
            detail.item_id =  issue.qbo_item_id
          end

          estimate .line_items << line_item

          service = Quickbooks::Service::Estimate.new(:company_id => Qbo.get_realm_id, :access_token => Qbo.get_auth_token)
          
          created_estimate = service.create(estimate)
          issue.custom_field_values = {CustomField.find_by_name("Estimate").id => created_estimate.doc_number}
          issue.save!
        end
      end
  end

   # After Issue Saved
  def controller_issues_edit_after_save(context={})
    issue = context[:issue]
    employee_id = User.find_by_id(issue.assigned_to_id).qbo_employee_id

    # Check to see if we have registered with QBO
    unless Qbo.first.nil? and issue.qbo_customer_id.nil? and issue.qbo_item_id.nil? and employee_id.nil? then
     
      # If the issue is closed, then create a new billable time activty for the customer
      if issue.status.is_closed? then
          bill_time(issue, employee_id)
      end
    end
  end
  
  # returns a new custom value
  def create_custom_value(name, value)
    custom_value = CustomValue.new
    custom_value.custom_field_id = 
    custom_value.value = value
    custom_value.customized_type = "Issue"
    return custom_value
  end
  
  # Create billable time entries
  def bill_time(issue, employee_id)
  
    # Get unbilled time entries
    spent_time = issue.time_entries.where(qbo_billed: [false, nil])
    spent_hours ||= spent_time.sum(:hours) || 0
    
    if spent_hours > 0 then
    
      # Prepare to create a new Time Activity
      time_service = Quickbooks::Service::TimeActivity.new(:company_id => Qbo.get_realm_id, :access_token => Qbo.get_auth_token)
      item_service = Quickbooks::Service::Item.new(:company_id => Qbo.get_realm_id, :access_token => Qbo.get_auth_token)
      time_entry = Quickbooks::Model::TimeActivity.new
    
      # Convert float spent time to hours and minutes
      hours  = spent_hours.to_i
      minutesDecimal = (( spent_hours - hours) * 60)
      minutes = minutesDecimal.to_i
      
      # update time entries billed status
      spent_time.each do |entry|
        entry.qbo_billed = true
        entry.save
      end
    
      item = item_service.fetch_by_id issue.qbo_item_id
      time_entry.description = "#{issue.tracker} ##{issue.id}: #{issue.subject}"
      time_entry.employee_id = employee_id
      time_entry.customer_id = issue.qbo_customer_id
      time_entry.billable_status = "Billable"
      time_entry.hours = hours
      time_entry.minutes = minutes
      time_entry.name_of = "Employee"
      time_entry.txn_date = Date.today
      time_entry.hourly_rate = item.unit_price
      time_entry.item_id = issue.qbo_item_id 
      time_entry.start_time = issue.start_date
      time_entry.end_time = Time.now
      time_service.create(time_entry)
    end
  end
end
