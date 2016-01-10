#The MIT License (MIT)
#
#Copyright (c) 2016 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class IssuesFormHookListener < Redmine::Hook::ViewListener

  # Edit Issue Form
  # Show a dropdown for quickbooks contacts
  def view_issues_form_details_bottom(context={})
    selected = ""
    
    QboCustomers.update_all
    #QboItem.update_all
 
    # Check to see if there is a quickbooks user attached to the issue
    if not context[:issue].qbo_customer_id.nil? then
      selected_customer = context[:issue].qbo_customer_id
      selected_item = context[:issue].qbo_item_id
    end

    # Generate the drop down list of quickbooks contacts
    select_customer = context[:form].select :qbo_customer_id, QboCustomers.all.pluck(:name, :id), :selected => selected_customer, include_blank: true
  
    # Generate the drop down list of quickbooks contacts
    select_item = context[:form].select :qbo_item_id, QboItem.all.pluck(:name, :id).reverse, :selected => selected_item, include_blank: true
    return "<p>#{select_customer}</p> <p>#{select_item}</p>"
  end

end