#The MIT License (MIT)
#
#Copyright (c) 2022 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Dynamically load all Hooks & Patches
ActiveSupport::Reloader.to_prepare do
  Dir::foreach(File.join(File.dirname(__FILE__), 'lib')) do |file|
    next unless /\.rb$/ =~ file
    require_dependency file
  end
end

Redmine::Plugin.register :redmine_qbo do
  
  # About
  name 'Redmine Quickbooks Online plugin'
  author 'Rick Barrette'
  description 'This is a plugin for Redmine to intergrate with Quickbooks Online to allow for seamless intergration CRM and invoicing of completed issues'
  version '1.1.0'
  url 'https://github.com/rickbarrette/redmine_qbo'
  author_url 'http://rickbarrette.org'
  settings :default => {'empty' => true}, :partial => 'qbo/settings'
  requires_redmine :version_or_higher => '4.0.0'
  
  # Add safe attributes for core models
  Issue.safe_attributes 'customer_id'
  Issue.safe_attributes 'qbo_item_id'
  Issue.safe_attributes 'qbo_estimate_id'
  Issue.safe_attributes 'qbo_invoice_id'
  Issue.safe_attributes 'vehicles_id'
  User.safe_attributes 'qbo_employee_id'
  TimeEntry.safe_attributes 'qbo_billed'
  Project.safe_attributes 'customer_id'
  Project.safe_attributes 'vehicle_id'

  # We are playing in the sandbox 
  #Quickbooks.sandbox_mode = true

  # set per_page globally
  WillPaginate.per_page = 20

  # Permissions for security
  permission :view_customers, :customers => :index, :public => false
  permission :add_customers, :customers => :new, :public => false
  permission :view_payments, :payments => :index, :public => false
  permission :add_payments, :payments => :new, :public => false
  permission :view_vehicles, :payments => :new, :public => false

  # Register top menu items
  menu :top_menu, :customers, { :controller => :customers, :action => :index }, :caption => 'Customers', :if => Proc.new {User.current.logged?}
  menu :top_menu, :vehicles, { :controller => :vehicles, :action => :index }, :caption => 'Vehicles', :if => Proc.new { User.current.logged? }
    
end
