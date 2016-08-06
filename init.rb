#The MIT License (MIT)
#
#Copyright (c) 2016 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

Redmine::Plugin.register :redmine_qbo do

  # View Hook Listeners
   require_dependency 'issues_form_hook_listener'
   require_dependency 'issues_save_hook_listener'
   require_dependency 'issues_show_hook_listener'
   require_dependency 'users_show_hook_listener'
   
   # Patches to the Redmine core.  Will not work in development mode
    require_dependency 'issue_patch'
    require_dependency 'user_patch'
    require_dependency 'query_patch'
    require_dependency 'pdf_patch'

    name 'Redmine Quickbooks Online plugin'
    author 'Rick Barrette'
    description 'This is a plugin for Redmine to intergrate with Quickbooks Online to allow for seamless intergration CRM and invoicing of completed issues'
    version '0.2.0'
    url 'https://github.com/rickbarrette/redmine_qbo'
    author_url 'http://rickbarrette.org'
    settings :default => {'empty' => true}, :partial => 'qbo/settings'

    # Add safe attributes
    Issue.safe_attributes 'customer_id'
    Issue.safe_attributes 'qbo_item_id'
    Issue.safe_attributes 'qbo_estimate_id'
    Issue.safe_attributes 'qbo_invoice_id'
    Issue.safe_attributes 'vehicles_id'
    User.safe_attributes 'qbo_employee_id'
    TimeEntry.safe_attributes 'qbo_billed'
    
    # We are playing in the sandbox 
    #Quickbooks.sandbox_mode = true
    
    # set per_page globally
    WillPaginate.per_page = 10

    # Register QBO top menu item
    #menu :top_menu, :qbo, { :controller => :qbo, :action => :index }, :caption => 'Quickbooks', :if => Proc.new { User.current.admin? }
    menu :top_menu, :customers, { :controller => :customers, :action => :index }, :caption => 'Customers', :if => Proc.new { User.current.logged? }
    menu :top_menu, :vehicles, { :controller => :vehicles, :action => :index }, :caption => 'Vehicles', :if => Proc.new { User.current.logged? }
    
    menu :application_menu, :new_customer, { :controller => :customers, :action => :new }, :caption => 'New Customer', :if => Proc.new { User.current.logged? }
    menu :application_menu, :new_payment, { :controller => :payments, :action => :new }, :caption => 'New Payment', :if => Proc.new { User.current.logged? }
    
    permission :customers, { :customers => [:index, :new] }, :public => false
    menu :project_menu, :customers, { :controller => 'customers', :action => 'new' }, :caption => 'New Customer', :after => :activity, :param => :project_id
    
    permission :payments, { :payments => [:index, :new] }, :public => false
    menu :project_menu, :payments, { :controller => 'payments', :action => 'new' }, :caption => 'New Payment', :after => :customers, :param => :project_id
end
