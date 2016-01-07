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

 require_dependency 'qbo_hook_listener'

  name 'Redmine Quickbooks Online plugin'
  author 'Rick Barrette'
  description 'This is a plugin for Redmine to intergrate with Quickbooks Online to allow for seamless intergration CRM and invoicing of completed issues'
  version '0.0.1'
  url 'https://github.com/rickbarrette/redmine_qbo'
  author_url 'http://rickbarrette.org'
  settings :default => {'empty' => true}, :partial => 'qbo/settings'

  # Add qbo_customer to the safe Issue Attributes list
  Issue.safe_attributes 'qbo_customer_id'

  # We are playing in the sandbox 
  Quickbooks.sandbox_mode = true

  # Register QBO top menu item
  menu :top_menu, :qbo, { :controller => 'qbo', :action => 'index' }, :caption => 'Quickbooks'

end
