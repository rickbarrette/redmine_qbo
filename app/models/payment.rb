#The MIT License (MIT)
#
#Copyright (c) 2016 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class Payment
  unloadable
  
  include ActiveModel::Model
  
  attr_accessor :errors, :customer_id, :account_id, :payment_method_id, :total_amount
  validates_presence_of :customer_id, :account_id, :payment_method_id, :total_amount
  validates :total_amount, numericality: true
  
  def save
    payment = Quickbooks::Model::Payment.new
    payment.customer_ref = payment_method_refQbo.get_base(:customer).service.fetch_by_id(@customer_id)
    payment.deposit_to_account_ref = payment_method_refQbo.get_base(:account).service.fetch_by_id(@account_id)
    payment.payment_method_ref = payment_method_refQbo.get_base(:payment_method).service.fetch_by_id(@payment_method_id)
    payment.total = @total_amount
    
    #begin
      Qbo.get_base(:payment).service.update(payment)
    #rescue Exception => e
    #  @errors.add(e.message)
    #end
  end
  
  def save!
    save
  end

  # Dummy stub to make validtions happy.
  def update_attribute
  end
  
  def new
    # TODO things & stuff
  end

end
