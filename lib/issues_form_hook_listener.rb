#The MIT License (MIT)
#
#Copyright (c) 2022 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class IssuesFormHookListener < Redmine::Hook::ViewListener

  # Edit Issue Form
  # Here we build the required form components before passing them to a partial view formatting. 
  def view_issues_form_details_bottom(context={})
    f = context[:form]

    # check project level customer ownership first
    # This is done to preload customer information if the entire project is dedicated to a customer
    if context[:project]
      selected_customer = context[:project].customer ? context[:project].customer.id : nil
      selected_vehicle = context[:project].vehicle ? context[:project].vehicle.id : nil
    end

    # Check to see if the issue already belongs to a customer
    selected_customer = context[:issue].customer ? context[:issue].customer.id  : nil
    selected_estimate = context[:issue].estimate ? context[:issue].estimate.id  : nil
    selected_vehicle = context[:issue].vehicles_id ? context[:issue].vehicles_id : nil

    # Load customer information
    customer = Customer.find_by_id(selected_customer) if selected_customer

    # Customer Name Text Box with database backed autocomplete
    search_customer = f.autocomplete_field :customer,
      autocomplete_customer_name_customers_path,
      :selected => selected_customer,
      :onchange => "updateIssueFrom('/issues/#{context[:issue].id}/edit.js', this)",
      :update_elements => { 
        :id => '#issue_customer_id', 
        :value => '#issue_customer' 
      }

    # Customer ID - Hidden Field
    customer_id = f.hidden_field :customer_id,
      :id => "issue_customer_id",
      :onchange => "updateIssueFrom('/issues/#{context[:issue].id}/edit.js', this)"

    # Load estimates & vehicles
    if context[:issue].customer
      if customer.vehicles
        vehicles = customer.vehicles.pluck(:name, :id)
      else
        vehicles = [nil].compact
      end
      estimates = customer.estimates.pluck(:doc_number, :id).sort! {|x, y| y <=> x}
    else
      vehicles = [nil].compact
      estimates = [nil].compact
    end

    # Generate the drop down list of quickbooks estimates & vehicles
    select_estimate = f.select :estimate_id, estimates, :selected => selected_estimate, include_blank: true
    vehicle = f.select :vehicles_id, vehicles, :selected => selected_vehicle, include_blank: true

    # Pass all prebuilt form components to our partial
    context[:controller].send(:render_to_string, {
      :partial => 'issues/form_hook',
        locals: {
          search_customer: search_customer, 
	        customer_id: customer_id, 
	        context: context, 
	        select_estimate: select_estimate,
	        vehicle: vehicle
        } 
      }
    )
  end
end
