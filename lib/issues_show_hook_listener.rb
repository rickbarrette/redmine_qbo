#The MIT License (MIT)
#
#Copyright (c) 2022 rick barrette
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
    issue = context[:issue]
    
    # Check to see if there is a quickbooks user attached to the issue
    if issue.customer
      customer = link_to issue.customer.name, customer_path( issue.customer.id )
    end
    
    # Estimate Number
    if issue.estimate
      estimate = issue.estimate.doc_number
      estimate_link = link_to estimate, estimate_path( issue.estimate.id ), :target => "_blank"
    end
    
    # Invoice Number
    invoice_link = ""
    if issue.invoice_ids
      issue.invoice_ids.each do |i|
        invoice = Invoice.find i
        invoice_link = invoice_link + link_to( invoice.doc_number, invoice_path( i ), :target => "_blank").to_s + " "
	      invoice_link = invoice_link.html_safe
      end
    end
    
    begin
      v = Vehicle.find(issue.vehicles_id)
      vehicle = link_to v.to_s, vehicle_path( v.id )
      vin = v.vin 
      notes = v.notes
    rescue
      #do nothing
    end
    
    split_vin = vin.scan(/.{1,9}/) if vin

    context[:controller].send(:render_to_string, {
      :partial => 'issues/show_details',
        locals: {
          customer: customer, 
	        estimate_link: estimate_link, 
	        invoice_link: invoice_link, 
	        vehicle: vehicle, 
	        split_vin: split_vin,
	        notes: notes
        } 
      })
  end
  
end
