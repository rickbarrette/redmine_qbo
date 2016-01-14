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

  # Additional context fields
  #   :issue  => the issue this is edited
  #   :f      => the form object to create additional fields
  #render_on :view_issues_show_details_bottom, :partial => 'hooks/redmine_qbo/_view_issues_show_details_bottom.html.erb'

  # View Issue
  # Display the quickbooks contact in the issue
  def view_issues_show_details_bottom(context={})
    issue = context[:issue]

    # Check to see if there is a quickbooks user attached to the issue
    #unless context[:issue].qbo_customer_id.nil?
      @customer = issue.qbo_customer.name
    #end
  
    # Check to see if there is a quickbooks item attached to the issue
    @item = issue.qbo_item.name
    
    # Estimate Number
    unless (issue.qbo_estimate.nil?)
      QboEstimate.update(issue.qbo_estimate.id)
      @estimate =  issue.qbo_estimate.doc_number
    end
    
    return "<div class=\"attributes\">
    <div class=\"qbo_customer_id attribute\">
    <div class=\"label\"><span>Customer</span>:</div>
    <div class=\"value\">#{@customer}</div>
  </div>
  
  <div class=\"qbo_item_id attribute\">
    <div class=\"label\"><span>Item</span>:</div>
    <div class=\"value\">#{@item}</div>
  </div>
  
    <div class=\"qbo_estimate_id attribute\">
        <div class=\"label\"><span>Estimate</span>:</div>
        <div class=\"value\">#{@estimate}</div>
    </div>
    </div>"
  end
  
end