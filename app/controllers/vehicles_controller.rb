#The MIT License (MIT)
#
#Copyright (c) 2024 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# This controller class will handle map management
class VehiclesController < ApplicationController

  include AuthHelper

  before_action :require_user

  def allowed_params
    params.require(:vehicle).permit(:year, :make, :model, :customer_id, :notes, :vin)
  end

  # display a list of all vehicles
  def index
    if params[:customer_id]
      begin
        @vehicles = Customer.find_by_id(params[:customer_id]).vehicles.paginate(:page => params[:page])
      rescue ActiveRecord::RecordNotFound
        render_404
      end
    end

    # search for a vehicle by vin
    if params[:search]
      @vehicles = Vehicle.search(params[:search]).paginate(:page => params[:page])
      if only_one_non_zero?(@vehicles)
        redirect_to @vehicles.first
      end
    end
  end

  # return an HTML form for creating a new vehicle
  def new
    @vehicle = Vehicle.new
    @customer = Customer.find_by_id(params[:customer_id]) if params[:customer_id]
  end

  # create a new vehicle
  def create
    @vehicle = Vehicle.new(allowed_params)
    if @vehicle.save
      flash[:notice] = "New Vehicle Created"
      redirect_to @vehicle
    else
      flash[:error] = @vehicle.errors.full_messages.to_sentence
      redirect_to Vehicle.find_by_vin @vehicle.vin
    end
  end

  # display a specific vehicle
  def show
    begin
      @vehicle = Vehicle.find_by_id(params[:id])
      @vin = @vehicle.vin.scan(/.{1,9}/) if @vehicle.vin
      @issues = @vehicle.issues.order(id: :desc)
      @closed_issues = (@issues - @issues.open)
    rescue 
      render_404
    end
  end

  # return an HTML form for editing a vehicle
  def edit
    begin
      @vehicle = Vehicle.find_by_id(params[:id])
      @customer = @vehicle.customer
    rescue 
      render_404
    end
  end

  # update a specific vehicle
  def update
    @customer = params[:customer]
    begin
      @vehicle = Vehicle.find_by_id(params[:id])
      if @vehicle.update(allowed_params)
        flash[:notice] = "Vehicle updated"
        redirect_to @vehicle
      else
        redirect_to edit_vehicle_path
      end
      #show any errors anyways
      flash[:error] = @vehicle.errors.full_messages.to_sentence unless @vehicle.errors.empty?
    rescue 
      render_404
    end
  end

  # delete a specific vehicle
  def destroy
    begin
      Vehicle.find_by_id(params[:id]).destroy
      flash[:notice] = "Vehicle deleted successfully"
      redirect_to action: :index
    rescue 
      render_404
    end
  end

  private

  # checks to see if there is only one item in an array
  # @return true if array only has one item
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
