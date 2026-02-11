#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module RedmineQbo
  module Hooks
    class IssuesHookListener < Redmine::Hook::ViewListener

      include IssuesHelper

        # Check the new issue form for a valid project.
        # This is added to help prevent 422 unprocessable entity errors when creating an issue 
        # See https://github.com/redmine/redmine/blob/84483d63828d0cb2efbf5bd786a2f0d22e34c93d/app/controllers/issues_controller.rb#L179
        def controller_issues_new_before_save(context={})

          Rails.logger.debug "RedmineQbo::Hooks::IssuesHookListener.controller_issues_new_before_save: Checking for nil project or tracker"
          Rails.logger.debug context[:params].inspect
          Rails.logger.debug context[:issue].inspect
          Rails.logger.debug context[:issue].project
          Rails.logger.debug context[:issue].tracker
          error = ""
          if context[:issue].project.nil?
            context[:issue].project ||= projects_for_select(context[:issue]).first
            Rails.logger.error I18n.t(:notice_error_project_nil) + context[:issue].project.to_s
            error = I18n.t(:notice_error_project_nil) + context[:issue].project.to_s
          end

          if context[:issue].tracker.nil?
            context[:issue].tracker ||= trackers_for_select(context[:issue]).first
            Rails.logger.error I18n.t(:notice_error_tracker_nil) + context[:issue].tracker.to_s
            error << "\n" 
            error << I18n.t(:notice_error_tracker_nil) + context[:issue].tracker.to_s
          end

          context[:controller].flash[:error] = error unless error.blank?
          Rails.logger.debug error unless error.blank?

          return context
        end

      # Edit Issue Form
      # Here we build the required form components before passing them to a partial view formatting. 
      def view_issues_form_details_bottom(context={})
        Rails.logger.debug "RedmineQbo::Hooks::IssuesHookListener.view_issues_form_details_bottom: Building form components for quickbooks customer, estimate, and invoice data"
        Rails.logger.debug context[:issue].inspect
        f = context[:form]
        issue = context[:issue]

        # Customer Name Text Box with database backed autocomplete
        # onchange event will update the hidden customer_id field
        search_customer = f.autocomplete_field :customer,
          autocomplete_customer_name_customers_path,
          selected: issue.customer,
          update_elements: { 
            id: '#issue_customer_id', 
            value: '#issue_customer' 
          }


        js_path = "updateIssueFrom('/issues/new.js', this)"
        js_path = "updateIssueFrom('#{escape_javascript update_issue_form_path(issue.project, issue)}', this)" unless issue.new_record?
        # This hidden field is used for the customer ID for the issue
        # the onchange event will reload the issue form via ajax to update the available estimates
        customer_id = f.hidden_field :customer_id,
          id: "issue_customer_id",
          onchange: js_path.html_safe

        # Generate the drop down list of quickbooks estimates owned by the selected customer
        select_estimate = f.select :estimate_id, 
          issue.customer ? issue.customer.estimates.pluck(:doc_number, :id).sort! {|x, y| y <=> x} : [], 
          selected: issue.estimate ? issue.estimate.id : nil, 
          include_blank: true
        
        # Pass all prebuilt form components to our partial
        context[:controller].send(:render_to_string, {
          partial: 'issues/form_hook',
            locals: {
              search_customer: search_customer, 
              customer_id: customer_id, 
              select_estimate: select_estimate
            } 
          }
        )
      end

      # View Issue
      # Displays the quickbooks customer, estimate, & invoices attached to the issue
      def view_issues_show_details_bottom(context={})
        issue = context[:issue]
        
        # Build a list of invoice links
        invoice_link = ""
        if issue.invoices
          issue.invoices.each do |i|
            invoice_link += "#{link_to i, i, target: :_blank}<br/>"
          end
        end
        
        context[:controller].send(:render_to_string, {
          partial: 'issues/show_details',
            locals: {
              customer: issue.customer ? link_to(issue.customer) : nil, 
              estimate_link: issue.estimate ? link_to(issue.estimate, issue.estimate, target: :_blank) : nil, 
              invoice_link: invoice_link.html_safe,
              issue: issue
            } 
          })
      end
      
    end
  end 
end