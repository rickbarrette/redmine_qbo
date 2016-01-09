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

   # New Issue Saved
  def controller_issues_edit_after_save(context={})
    issue = context[:issue]
    qbo = Qbo.first

    # Check to see if we have registered with QBO
    if not qbo.nil? then
      
      # Prepare to create a new Time Activity
      time_service = Quickbooks::Service::TimeActivity.new(:company_id => qbo.realmId, :access_token => Qbo.get_auth_token)
      item_service = Quickbooks::Service::Item.new(:company_id => qbo.realmId, :access_token => Qbo.get_auth_token)
      time_entry = Quickbooks::Model::TimeActivity.new
      item = item_service.fetch_by_id issue.qbo_item_id

      # Get unbilled time entries
      spent_time = issue.time_entries.where(qbo_billed: [false, nil])
      spent_hours ||= spent_time.sum(:hours) || 0
      
      # Convert float spent time to hours and minutes
      hours  = spent_hours.to_i
      minutesDecimal = (( spent_hours - hours) * 60)
      minutes = minutesDecimal.to_i
      
      # update time entries billed status
      spent_time.each do |entry|
        entry.qbo_billed = true
        entry.save
      end
      
      employee_id = User.find_by_id(issue.assigned_to_id).qbo_employee_id
     
      # If the issue is closed, then create a new billable time activty for the customer
      # TODO Add configuration settings for employee_id, hourly_rate, item_id
      if issue.status.is_closed? and not issue.qbo_customer_id.nil? and not issue.qbo_item_id.nil? and not employee_id.nil? and spent_hours > 0 then
        time_entry.description = "Ticket ##{issue.id}: #{issue.subject}"
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
end
