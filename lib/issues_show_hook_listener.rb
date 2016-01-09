#The MIT License (MIT)
#
#Copyright (c) 2016 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class IssuesShowHookListener < Redmine::Hook::ViewListener

  # View Issue
  # Display the quickbooks contact in the issue
  def view_issues_show_details_bottom(context={})
    value = ""

    # Check to see if there is a quickbooks user attached to the issue
    if not context[:issue].qbo_customer_id.nil? then
      value = QboCustomers.find_by_id(context[:issue].qbo_customer_id).name
    end
  
    output = content_tag(:div, content_tag(:div, content_tag(:div, content_tag(:span,"Customer") + ":", class:"label") +  content_tag(:div, value, class:"value") , class:"qbo_customer_id attribute"), class:"attributes")
    
    # Check to see if there is a quickbooks user attached to the issue
    if not context[:issue].qbo_customer_id.nil? then
      value = QboItem.find_by_id(context[:issue].qbo_item_id).name
    end
    
    output << content_tag(:div, content_tag(:div, content_tag(:div, content_tag(:span,"Item") + ":", class:"label") +  content_tag(:div, value, class:"value") , class:"qbo_item_id attribute"), class:"attributes")
  
    # Display the Customers name in the Issue attributes
    return  output
  end

end