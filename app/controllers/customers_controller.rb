#The MIT License (MIT)
#
#Copyright (c) 2016 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# This controller class will handle map management
class CustomersController < ApplicationController
  unloadable
  
  include AuthHelper
  
  before_filter :require_user
  
  # display a list of all customers
  def index
    @customers = Customer.paginate(:page => params[:page])
  end
  
  def new
    @customer = Customer.new
  end
  
  def create
    @customer = Customer.new(params[:customer])
    if @customer.save
      flash[:notice] = "New Customer Created"
      redirect_to @customer
    else
      flash[:error] = @customer.errors.full_messages.to_sentence 
      redirect_to new_customer_path
    end
  end
  
  # display a specific customer
  def show
    @customer = Customer.find_by_id(params[:id])
    if @customer
      @vehicles = @customer.vehicles.paginate(:page => params[:page])
      @issues = @customer.issues
    else
      flash[:error] = "Customer Not Found"  
      render :index
    end
  end
  
  # return an HTML form for editing a customer
  def edit
    @customer = Customer.find_by_id(params[:id])
  end
  
  # update a specific customer
  def update
    @customer = Customer.find_by_id(params[:id])
    if @customer.update_attributes(params[:vehicle])
      flash[:notice] = "Customer updated"
      redirect_to @customer
    else
      redirect_to edit_customer_path
    end
    flash[:error] = @customer.errors.full_messages.to_sentence if @customer.errors
  end
  
  def destroy
    begin
      Customer.find_by_id(params[:id]).destroy
      flash[:notice] = "Customer deleted successfully"
    rescue
      flash[:error] = "No Customer Found"
    end
    redirect_to action: :index

  end

end
