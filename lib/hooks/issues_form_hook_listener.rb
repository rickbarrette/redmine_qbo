#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module Hooks

  class IssuesFormHookListener < Redmine::Hook::ViewListener

   include IssuesHelper

    # Edit Issue Form
    # Here we build the required form components before passing them to a partial view formatting. 
    def view_issues_form_details_bottom(context={})
      f = context[:form]
      issue = context[:issue]

      # check project level customer ownership first
      # This is done to preload customer information if the entire project is dedicated to a customer
      if context[:project]
        selected_customer = context[:project].customer ? context[:project].customer.id : nil
      end

      # Check to see if the issue already belongs to a customer
      selected_customer = issue.customer ? issue.customer.id  : nil
      selected_estimate = issue.estimate ? issue.estimate.id  : nil
      
      # Gernerate edit.js link
      js_link = "updateIssueFrom('#{escape_javascript update_issue_form_path(issue.project, issue)}', this)"

      # Load customer information
      customer = Customer.find_by_id(selected_customer) if selected_customer

      # Customer Name Text Box with database backed autocomplete
      search_customer = f.autocomplete_field :customer,
        autocomplete_customer_name_customers_path,
        :selected => selected_customer,
        :onchange => js_link,
        :update_elements => { 
          :id => '#issue_customer_id', 
          :value => '#issue_customer' 
        }

      # Customer ID - Hidden Field
      customer_id = f.hidden_field :customer_id,
        :id => "issue_customer_id",
        :onchange => js_link

      # Load estimates
      if issue.customer
        estimates = customer.estimates.pluck(:doc_number, :id).sort! {|x, y| y <=> x}
      else
        estimates = [nil].compact
      end

      # Generate the drop down list of quickbooks estimates
      select_estimate = f.select :estimate_id, estimates, :selected => selected_estimate, include_blank: true
      
      # Pass all prebuilt form components to our partial
      context[:controller].send(:render_to_string, {
        :partial => 'issues/form_hook',
          locals: {
            search_customer: search_customer, 
            customer_id: customer_id, 
            js_link: js_link, 
            select_estimate: select_estimate
          } 
        }
      )
    end
  end

end