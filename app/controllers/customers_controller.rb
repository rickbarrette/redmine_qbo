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
  
  default_search_scope :names
  
  autocomplete :name, :full => true
  
  # display a list of all customers
  def index
    if params[:search]
      @customers = Customer.search(params[:search]).paginate(:page => params[:page])
      if only_one_non_zero?(@customers)
        redirect_to @customers.first
      end
    end
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
    begin
      @customer = Customer.find_by_id(params[:id])
      @vehicles = @customer.vehicles.paginate(:page => params[:page])
      @issues = @customer.issues
    rescue ActiveRecord::RecordNotFound
      render_404
    end
  end
  
  # return an HTML form for editing a customer
  def edit
    begin
      @customer = Customer.find_by_id(params[:id])
    rescue ActiveRecord::RecordNotFound
      render_404
    end
  end
  
  # update a specific customer
  def update
    begin
      @customer = Customer.find_by_id(params[:id])
      if @customer.update_attributes(params[:customer])
        flash[:notice] = "Customer updated"
        redirect_to @customer
      else
        redirect_to edit_customer_path
        flash[:error] = @customer.errors.full_messages.to_sentence if @customer.errors
      end
    rescue ActiveRecord::RecordNotFound
      render_404
    end
  end
  
  def destroy
    begin
      Customer.find_by_id(params[:id]).destroy
      flash[:notice] = "Customer deleted successfully"
      redirect_to action: :index
    rescue ActiveRecord::RecordNotFound
      render_404
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
