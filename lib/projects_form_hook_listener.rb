#The MIT License (MIT)
#
#Copyright (c) 2017 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class ProjectsFormHookListener < Redmine::Hook::ViewListener
  
  # Load the javascript
  def view_layouts_base_html_head(context = {})
    js = javascript_include_tag 'application', :plugin => 'redmine_qbo'
    js += javascript_include_tag 'autocomplete-rails', :plugin => 'redmine_qbo'
    return js
  end
  
  # Edit Issue Form
  # Show a dropdown for quickbooks contacts
  def view_projects_form(context={})
    f = context[:form]
 
    # Check to see if there is a quickbooks user attached to the issue
    selected_customer =  context[:project].customers_id ? context[:project].customers_id  : nil
    selected_vehicle = context[:project].vehicles_id ? context[:project].vehicles_id : nil
    
    # Load customer information
    customer = Customer.find_by_id(selected_customer) if selected_customer   
    search_customer = f.autocomplete_field :customer, autocomplete_customer_name_customers_path, :selected => selected_customer, :update_elements => {:id => '#project_customer_id', :value => '#project_customer'}
    customer_id = f.hidden_field :customers_id, :id => "project_customer_id"
    
    if context[:project].customer
      vehicles = customer.vehicles.pluck(:name, :id).sort!
    else
      vehicles = [nil].compact
    end
    
    vehicle = f.select :vehicles_id, vehicles, :selected => selected_vehicle, include_blank: true
    
    return "<p><label for=\"project_customer\">Customer</label>#{search_customer} #{customer_id}</p> <p>#{vehicle}</p>"
end
end
