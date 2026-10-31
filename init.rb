#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Redmine::Plugin.register :redmine_qbo do
  
  # About
  name 'Redmine QBO plugin'
  author 'Rick Barrette'
  description 'A pluging for Redmine to connect with QuickBooks Online: customers, time activities for billable hours when an issue is closed, and estimates, invoices and payments written in Redmine'
  version '2026.11.4'
  url 'https://github.com/rickbarrette/redmine_qbo'
  author_url 'https://barrettefabrication.com'
  settings default: {empty: true}, partial: 'qbo/settings'
  requires_redmine version_or_higher: '6.1.0'
  
  # Add safe attributes for core models
  Issue.safe_attributes :customer_id
  Issue.safe_attributes :estimate_id
  Issue.safe_attributes :invoice_id
  User.safe_attributes :employee_id
  TimeEntry.safe_attributes :billed
  
  # set per_page globally
  WillPaginate.per_page = 20

  # Global Permissions
  # autocomplete and the filter_* actions feed the customer, estimate and invoice pickers on issue forms
  permission :view_customers, { customers: [:index, :show, :autocomplete,
                                            :filter_estimates_by_customer, :filter_invoices_by_customer] }, global: true
  permission :add_customers, { customers: [:new, :create] }, global: true
  permission :edit_customers, { customers: [:edit, :update] }, global: true
  permission :share_issues_with_customers, { customers: [:share] }, global: true

  # Project permissions
  permission :bill_issues, { qbo: [:bill] }

  # Billing (global): estimates, invoices, payments, issues from estimates
  # customer_info and items feed the customer details and product/service search on the estimate/invoice editor
  permission :write_estimates, { qbo_estimates: [:new, :create, :edit, :update, :customer_info, :items] }, global: true
  permission :send_estimates, { qbo_estimates: [:send_email] }, global: true
  permission :create_estimate_issues, { qbo_estimates: [:issues_preview, :create_issues] }, global: true
  permission :write_invoices, { qbo_invoices: [:new, :create, :edit, :update, :import_options],
                                qbo_estimates: [:customer_info, :items] }, global: true
  permission :send_invoices, { qbo_invoices: [:send_email] }, global: true
  permission :view_payments, { qbo_payments: [:index, :show, :pdf] }, global: true
  permission :receive_payments, { qbo_payments: [:index, :new, :create, :show, :pdf, :open_invoices],
                                  qbo_estimates: [:customer_info] }, global: true
  permission :view_business_reports, { qbo_reports: [:index] }, global: true
  # The product/service list, accounts and their syncs are admin-only (see ItemsController, AccountsController)
  
  # Register top menu items
  menu :top_menu, :customers, { controller: :customers, action: :index }, caption: :label_customers, if: Proc.new {User.current.allowed_to?(:view_customers, nil, global: true)}
  menu :top_menu, :qbo_reports, { controller: :qbo_reports, action: :index }, caption: :label_business_report,
       after: :customers, if: Proc.new { User.current.allowed_to?(:view_business_reports, nil, global: true) }
    
  Redmine::Search.map do |search|
    search.register :customers
  end

end

RedmineQbo.setup
