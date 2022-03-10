#The MIT License (MIT)
#
#Copyright (c) 2022 rick barrette
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
  helper :issues
  helper :journals
  helper :projects
  helper :custom_fields
  helper :issue_relations
  helper :watchers
  helper :attachments
  helper :queries
  include QueriesHelper
  helper :repositories
  helper :sort
  include SortHelper
  helper :timelog

  before_action  :add_customer, :only => :new
  before_action  :view_customer, :except => [:new, :view]
  skip_before_action :verify_authenticity_token, :check_if_login_required, :only => [:view]

  default_search_scope :names

  autocomplete :customer, :name, :full => true, :extra_data => [:id]

  def allowed_params
    params.require(:customer).permit(:name, :email, :primary_phone, :mobile_phone, :phone_number)
  end

  # getter method for a customer's vehicles
  # used for customer autocomplete field / issue form
  def filter_vehicles_by_customer
    @filtered_vehicles = Vehicle.all.where(customer_id: params[:selected_customer])
  end

  # getter method for a customer's invoices
  # used for customer autocomplete field / issue form
  def filter_invoices_by_customer
    @filtered_invoices = Invoice.all.where(customer_id: params[:selected_customer])
  end

  # getter method for a customer's estimates
  # used for customer autocomplete field / issue form
  def filter_estimates_by_customer
    @filtered_estimates = Estimate.all.where(customer_id: params[:selected_customer])
  end

  # display a list of all customers
  def index
    if params[:search]
      @customers = Customer.search(params[:search]).paginate(:page => params[:page])
      if only_one_non_zero?(@customers)
        redirect_to @customers.first
      end
    end
  end

  # initialize a new customer
  def new
    @customer = Customer.new
  end

  # create a new customer
  def create
    @customer = Customer.new(allowed_params)
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
      @issues = @customer.issues.order(id: :desc)
      @billing_address = address_to_s(@customer.billing_address)
      @shipping_address = address_to_s(@customer.shipping_address)
      @closed_issues = (@issues - @issues.open)
    rescue 
      render_404
    end
  end

  # return an HTML form for editing a customer
  def edit
    begin
      @customer = Customer.find_by_id(params[:id])
    rescue 
      render_404
    end
  end

  # update a specific customer
  def update
    begin
      @customer = Customer.find_by_id(params[:id])
      if @customer.update_attributes(allowed_params)
        flash[:notice] = "Customer updated"
        redirect_to @customer
      else
        redirect_to edit_customer_path
        flash[:error] = @customer.errors.full_messages.to_sentence if @customer.errors
      end
    rescue 
      render_404
    end
  end

  # delete a customer
  def destroy
    begin
      Customer.find_by_id(params[:id]).destroy
      flash[:notice] = "Customer deleted successfully"
      redirect_to action: :index
    rescue 
      render_404
    end
  end

  # creates new customer view tokens, removes expired tokens & redirects to newly created customer view with new token.
  def share

    Thread.new do
      logger.debug "Removing expired customer tokens"
      CustomerToken.remove_expired_tokens
      ActiveRecord::Base.connection.close
    end

    begin
      issue = Issue.find_by_id(params[:id])
      redirect_to view_path issue.share_token.token
    rescue
      render_404
    end
  end
  
  # displays an issue for a customer with a provided security CustomerToken
  def view

    User.current = User.find_by lastname: 'Anonymous'

    @token = CustomerToken.where("token = ? and expires_at > ?", params[:token], Time.now)
    @token = @token.first
    if @token
      session[:token] = @token.token
      @issue = Issue.find @token.issue_id
      @journals = @issue.journals.
                  preload(:details).
                  preload(:user => :email_address).
                  reorder(:created_on, :id).to_a
      @journals.each_with_index {|j,i| j.indice = i+1}
      @journals.reject!(&:private_notes?) unless User.current.allowed_to?(:view_private_notes, @issue.project)
      Journal.preload_journals_details_custom_fields(@journals)
      @journals.select! {|journal| journal.notes? || journal.visible_details.any?}
      @journals.reverse! if User.current.wants_comments_in_reverse_order?

      @changesets = @issue.changesets.visible.preload(:repository, :user).to_a
      @changesets.reverse! if User.current.wants_comments_in_reverse_order?

      @relations = @issue.relations.select {|r| r.other_issue(@issue) && r.other_issue(@issue).visible? }
      @allowed_statuses = @issue.new_statuses_allowed_to(User.current)
      @priorities = IssuePriority.active
      @time_entry = TimeEntry.new(:issue => @issue, :project => @issue.project)
      @relation = IssueRelation.new
    else
      render_403
    end
  end

  private

  # redmine permission - add customers
  def add_customer
    global_check_permission(:add_customers)
  end

  # redmine permission - view customers
  def view_customer
    global_check_permission(:view_customers)
  end

  # checks to see if there is only one item  in an array
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

  # format a quickbooks address to a human readable string
  def address_to_s (address)
    return if address.nil?
    string =  address.line1
    string << "\n" + address.line2 if address.line2
    string << "\n" + address.line3 if address.line3
    string << "\n" + address.line4 if address.line4
    string << "\n" + address.line5 if address.line5
    string << " " + address.city
    string << ", " + address.country_sub_division_code
    string << " " + address.postal_code
    return string
  end

end
