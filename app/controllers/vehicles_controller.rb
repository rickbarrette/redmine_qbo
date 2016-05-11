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
    @vehicles = Vehicle.paginate(:page => params[:page])
  end

  # return an HTML form for creating a new vehicle
  def new
    @vehicle = Vehicle.new
    @customers = Customer.all.order(:name)
  end

  # create a new vehicle
  def create
    @vehicle = Vehicle.new(params[:vehicle])
    if @vehicle.save
      flash[:notice] = "New Vehicle Created"
      redirect_to @vehicle
    else
      flash[:error] = @vehicle.errors.full_messages.to_sentence 
      redirect_to new_vehicle_path
    end
  end
  
  # display a specific vehicle
  def show
    begin
      @vehicle = Vehicle.find_by_id(params[:id])
    rescue ActiveRecord::RecordNotFound
      render_404
    end
  end
  
  # return an HTML form for editing a vehicle
  def edit
    begin
      @vehicle = Vehicle.find_by_id(params[:id])
      @customers = Customer.all.order(:name)
    rescue ActiveRecord::RecordNotFound
      render_404
    end
  end
  
  # update a specific vehicle
  def update
    @customer = params[:customer]
    @vehicle = Vehicle.find_by_id(params[:id])
    if @vehicle.update_attributes(params[:vehicle])
      flash[:notice] = "Vehicle updated"
      redirect_to @vehicle
    else
      flash[:error] = @vehicle.errors.full_messages.to_sentence if @vehicle.errors
      redirect_to edit_vehicle_path
    end
  end  

  # delete a specific vehicle
  def destroy
    begin
      Vehicle.find_by_id(params[:id]).destroy
      flash[:notice] = "Vehicle deleted successfully"
      redirect_to action: :index
    rescue ActiveRecord::RecordNotFound
      render_404
    end
  end

end
