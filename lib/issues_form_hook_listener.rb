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
  
  # Load the javascript
  def view_layouts_base_html_head(context = {})
    js = javascript_include_tag 'vehicles.coffee', :plugin => 'redmine_qbo' 
    js << javascript_include_tag 'update_vehicles.coffee', :plugin => 'redmine_qbo'
    return js
  end
  
  # Edit Issue Form
  # Show a dropdown for quickbooks contacts
  def view_issues_form_details_bottom(context={})
    f = context[:form]
 
    # Check to see if there is a quickbooks user attached to the issue
    selected_customer =  context[:issue].customer ? context[:issue].customer.id  : nil
    selected_estimate =  context[:issue].qbo_estimate ? context[:issue].qbo_estimate.id  : nil
    selected_vehicle = context[:issue].vehicles_id ? context[:issue].vehicles_id : nil
    
    # Load customer information without callbacks
    customer = Customer.find_by_id(selected_customer) if selected_customer
    select_customer = f.select :customer_id, Customer.all.pluck(:name, :id).sort, :selected => selected_customer, include_blank: true
    
    # Generate the drop down list of quickbooks extimates
    select_estimate = f.select :qbo_estimate_id, QboEstimate.all.pluck(:doc_number, :id).sort! {|x, y| y <=> x}, :selected => selected_estimate, include_blank: true
    
    if context[:issue].customer
      vehicles = customer.vehicles.pluck(:name, :id).sort! 
    else
      vehicles = Vehicle.all.order(:name).pluck(:name, :id)
    end
    
    vehicle = f.select :vehicles_id, vehicles, :selected => selected_vehicle, include_blank: true
    
    return "<p>#{select_customer}</p> <p>#{select_estimate}</p> <p>#{vehicle}</p>"
  end
end
