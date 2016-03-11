#The MIT License (MIT)
#
#Copyright (c) 2016 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class IssuesFormHookListener < Redmine::Hook::ViewListener

  # Edit Issue Form
  # Show a dropdown for quickbooks contacts
  def view_issues_form_details_bottom(context={})
    # Update the customer and item database
    QboCustomer.update_all
    #QboItem.update_all
    QboInvoice.update_all
    QboEstimate.update_all
 
    # Check to see if there is a quickbooks user attached to the issue
    @selected_customer = context[:issue].qbo_customer.id  if context[:issue].qbo_customer
    @selected_item = context[:issue].qbo_item.id  if context[:issue].qbo_item
    @selected_invoice = context[:issue].qbo_invoice ? context[:issue].qbo_invoice.id  : nil
    @selected_estimate =  context[:issue].qbo_estimate ? context[:issue].qbo_estimate.id  : nil
    
    # Generate the drop down list of quickbooks customers
    @select_customer = context[:form].select :qbo_customer_id, QboCustomer.all.pluck(:name, :id), :selected => @selected_customer, include_blank: true
  
    # Generate the drop down list of quickbooks items
    @select_item = context[:form].select :qbo_item_id, QboItem.all.pluck(:name, :id), :selected => @selected_item, include_blank: true
    
    # Generate the drop down list of quickbooks invoices
    @select_invoice = context[:form].select :qbo_invoice_id, QboInvoice.all.pluck(:doc_number, :id).sort! {|x, y| y <=> x}, :selected => @selected_invoice, include_blank: true
    
    # Generate the drop down list of quickbooks extimates
    @select_estimate = context[:form].select :qbo_estimate_id, QboEstimate.all.pluck(:doc_number, :id).sort! {|x, y| y <=> x}, :selected => @selected_estimate, include_blank: true
    
    
    return "<p>#{@select_customer}</p> <p>#{@select_item}</p> <p>#{@select_invoice}</p> <p>#{@select_estimate}</p>"
  end
end
