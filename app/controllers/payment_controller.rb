#The MIT License (MIT)
#
#Copyright (c) 2016 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
class PaymentController < ApplicationController
  unloadable
  
  include AuthHelper
  
  before_filter :require_user

  def new
    @customers = Customers.all
    
    account_base = Qbo.get_base(:account).service
    @accounts = account_base.all
    
    payment_method_base = Qbo.get_base(:payment_method).service
    @payment_methods = payment_method_base.all
  end
  
  def create
    @customer = Customer.find_by_id(params[:customer_id])
    if @customer
      # TODO things
    else
      flash[:error] = @customer.errors.full_messages.to_sentence 
      redirect_to new_payment_path
    end
  end
  
  private
  
  def only_one_non_zero?( array )
    found_non_zero = false
    array.each do |val|
      if val!=0
        return false if found_non_zero
        found_non_zero = true
      end
    end
    found_non_zero
  end

end
