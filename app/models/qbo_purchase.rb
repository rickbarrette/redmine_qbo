#The MIT License (MIT)
#
#Copyright (c) 2016 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class QboPurchase < ActiveRecord::Base
  unloadable
  belongs_to :issues
  belongs_to :qbo_customer
  attr_accessible :description
  validates_presence_of :id, :line_id, :description, :qbo_customer_id
  
  def get_base
    Qbo.get_base(:purchase)
  end

  def get_purchase(id)
    get_base.service.find_by_id(id)
  end

  def sync
   QboPurchase.get_base.service.all.each { |purchase|
      
      purchase.line_items.all? { |line_item|
        
        detail = line_item.account_based_expense_line_detail ? line_item.account_based_expense_line_detail : line_item.item_based_expense_line_detail
        
        if detail.billable_status =  "Billable"
            qbo_purchase = find_or_create_by(id: purchase.id)
            qbo_purchase.line_id = line_item.id
            qbo_purchase.description = line_item.description
            qbo_purchase.qbo_customer_id = detail.customer_ref
            
            #TODO attach to issues
            #qbo_purchase.issue_id = Issue.find_by_invoice()
            
            qbo_purchase.save
        end
      }
    }
  end
end
