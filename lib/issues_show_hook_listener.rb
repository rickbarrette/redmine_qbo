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
    if issue.customer
      customer =  link_to issue.customer.name, "#{Redmine::Utils::relative_url_root}/customers/#{issue.customer.id}"
    end
    
    # Estimate Number
    if issue.qbo_estimate
      estimate =  issue.qbo_estimate.doc_number
      estimate_link = link_to estimate, "#{Redmine::Utils::relative_url_root}/qbo/estimate/#{issue.qbo_estimate.id}", :target => "_blank"
    end
    
    # Invoice Number
    invoice_link = ""
    if issue.qbo_invoice_ids
      issue.qbo_invoice_ids.each do |i|
        invoice = QboInvoice.find i
        invoice_link = invoice_link + link_to( invoice.doc_number, "#{Redmine::Utils::relative_url_root}/qbo/invoice/#{i}", :target => "_blank").to_s + " "
      end
    end
    
    begin
      v = Vehicle.find(issue.vehicles_id)
      vehicle = link_to v.to_s, "#{Redmine::Utils::relative_url_root}/vehicles/#{v.id}"
      vin = v.vin 
      notes = v.notes
    rescue
      #do nothing
    end
    
    split_vin = vin.scan(/.{1,9}/) if vin
    
    return "
    <div class=\"attributes\">
    
      <div class=\"customer_id attribute\">
        <div class=\"label\"><span>Customer</span>:</div>
        <div class=\"value\">#{customer}</div>
      </div>

      <div class=\"qbo_estimate_id attribute\">
        <div class=\"label\"><span>Estimate</span>:</div>
        <div class=\"value\">#{estimate_link}</div>
      </div>
        
      <div class=\"qbo_invoice_id attribute\">
        <div class=\"label\"><span>Invoice</span>:</div>
        <div class=\"value\">#{invoice_link}</div>
      </div>
      
      <br/>

      <div class=\"vehicle attribute\">
        <div class=\"label\"><span>Vehicle</span>:</div>
        <div class=\"value\">#{vehicle}</div>
      </div>
        
      <div class=\"vehicle_vin attribute\">
        <div class=\"label\"><span>VIN</span>:</div>
        <div class=\"value\">#{split_vin[0] if split_vin}<b>#{split_vin[1] if split_vin}</b></div>
      </div>
      
      <div class=\"vehicle_notes attribute\">
        <div class=\"label\"><span>Notes</span>:</div>
        <div class=\"value\">#{notes}</div>
      </div>
    </div>    "
  end
  
  def view_issues_show_description_bottom(context={})
    bill_button = button_to "Bill Time", "#{Redmine::Utils::relative_url_root}/qbo/bill/#{context[:issue].id}", method: :get if User.current.admin?
    share_button = button_to "Share", "#{Redmine::Utils::relative_url_root}/customers/view/#{context[:issue].share_token.token}", method: :get if User.current.logged?
    return "<br/> #{bill_button} #{share_button}"
  end
  
end
