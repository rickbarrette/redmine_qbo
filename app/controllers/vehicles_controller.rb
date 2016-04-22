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
class VehiclesController < ApplicationController
  unloadable
  
  include AuthHelper
  
  before_filter :require_user
  
  # display a list of all vehicles
  def index

  end

  # return an HTML form for creating a new vehicle
  def new
    @vehicle = Vehicle.new
  end

  # create a new vehicle
  def create
    @vehicle = Vehicle.new(params[:vehicle])
    @vehicle.save!
    redirect_to @vehicle
  end
  
  # display a specific vehicle
  def show
    @vehicle = Vehicle.find_by_id(params[:id])
    @customer = @vehicle.qbo_customer.name if @vehicle.qbo_customer
  end
  
  # return an HTML form for editing a vehicle
  def edit
    @vehicle = Vehicle.find_by_id(params[:id])
    @customer = @vehicle.qbo_customer.id if @vehicle.qbo_customer
  end
  
  # update a specific vehicle
  def update
    @vehicle = Vehicle.find_by_id(params[:id])
    if @vehicle.update_attributes(params[:vehicle])
      flash[:success] = "Vehicle updated"
      redirect_to @vehicle
    else
      render :edit
    end
  end  

  # delete a specific vehicle
  def destroy 
    v = Vehicle.find_by_id(params[:id])
    if v != nil
      v.destroy
      flash.now[:notice] = "Vehicle deleted successfully"
    else
      flash.now[:error] = "No Vehicle Found"
    end
    redirect_to :index
  end

end
