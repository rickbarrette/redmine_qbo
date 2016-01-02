#The MIT License (MIT)
#
#Copyright (c) 2016 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class QboHookListener < Redmine::Hook::ViewListener

  # Edit Issue Form
  # Show a dropdown for quickbooks contacts
  def view_issues_form_details_bottom(context={})
    selected = ""
 
    # Check to see if there is a quickbooks user attached to the issue
    if not context[:issue].qbo_customer_id.nil? then
      selected = context[:issue].qbo_customer_id
    end

    # Generate the drop down list of quickbooks contacts
    select = context[:form].select :qbo_customer_id, QboCustomers.all.pluck(:name, :id), :selected => selected, include_blank: true
    return "<p>#{select}</p>"
  end

  # View Issue
  # Display the quickbooks contact in the issue
  def view_issues_show_details_bottom(context={})
    value = ""

    # Check to see if there is a quickbooks user attached to the issue
    if not context[:issue].qbo_customer_id.nil? then
      value = QboCustomers.find_by_id(context[:issue].qbo_customer_id).name
    end

    # Display the Customers name in the Issue attributes
    return  content_tag(:div, content_tag(:div, content_tag(:div, content_tag(:span,"Customer") + ":", class:"label") +  content_tag(:div, value, class:"value") , class:"qbo_customer_id attribute"), class:"attributes")
  end

  # New Issue Saved
  def controller_issues_edit_after_save(context={})
    issue = context[:issue]
    qbo = Qbo.first

   qb_oauth_consumer = OAuth::Consumer.new(Setting.plugin_redmine_qbo['settingsOAuthConsumerKey'], Setting.plugin_redmine_qbo['settingsOAuthConsumerSecret'], {
     :site                 => "https://oauth.intuit.com",
     :request_token_path   => "/oauth/v1/get_request_token",
     :authorize_url        => "https://appcenter.intuit.com/Connect/Begin",
     :access_token_path    => "/oauth/v1/get_access_token"
   })

    # Check to see if we have registered with QBO
    if not qbo.nil? then
      # Connect to QBO  
      oauth_client = OAuth::AccessToken.new(qb_oauth_consumer, qbo.token, qbo.secret)

      # Prepare to create a new Time Activity
      time_service = Quickbooks::Service::TimeActivity.new(:company_id => qbo.realmId, :access_token => oauth_client)
      time_entry = Quickbooks::Model::TimeActivity.new

      # Convert float spent time to hours and minutes
      hours = issue.spent_hours.to_i
      minutesDecimal = (( issue.spent_hours - hours) * 60)
      minutes = minutesDecimal.to_i
     
      # If the issue is closed, then create a new billable time activty for the customer
      # TODO Add configuration settings for employee_id, hourly_rate, item_id
      if issue.status.is_closed? then
         time_entry.description = issue.subject
         time_entry.employee_id = 59
         time_entry.customer_id = issue.qbo_customer_id
         time_entry.billable_status = "Billable"
         time_entry.hours = hours
         time_entry.minutes = minutes
         time_entry.name_of = "Employee"
         time_entry.txn_date = Date.today
         time_entry.hourly_rate = 50
         time_entry.item_id = 19 
         time_entry.start_time = issue.start_date
         time_entry.end_time = Time.now
         time_service.create(time_entry)
      end
    end
  end
end
