#The MIT License (MIT)
#
#Copyright (c) 2016 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
class PaymentsController < ApplicationController
  unloadable
  
  include AuthHelper
  
  before_filter :find_project, :authorize

  def new
    @payment = Payment.new
    
    @customers = Customer.all.sort_by &:name
    
    @accounts = Qbo.get_base(:account).service.query("SELECT Id, Name FROM Account WHERE AccountType = 'Bank' Order By Name")
    
    @payment_methods = Qbo.get_base(:payment_method).service.all
  end
  
  def create
    @payment = Payment.new(params[:payment])
    if @payment.save
      flash[:notice] = "Payment Saved"
      redirect_to Customer.find_by_id(@payment.customer_id)
    else
      flash[:error] = @payment.errors.full_messages.to_sentence 
      redirect_to new_customer_path
end
  end
  
  private

  def find_project
    # @project variable must be set before calling the authorize filter
    @project = Project.find(params[:project_id])
  end
  
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
