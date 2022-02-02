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
class LineItemsController < ApplicationController
  unloadable
  
  include AuthHelper
  
  before_action :require_user
  
  # display all line items for an issue
  def index
    if params[:issue_id]
      begin
        @line_items = Issue.find_by_id(params[:issue_id]).line_items
      rescue ActiveRecord::RecordNotFound
        render_404
      end
    end
  end

  # return an HTML form for creating a new line item
  def new
    @line_item = LineItem.new
  end

  # create a new line item
  def create
    @line_item = LineItem.new(params[:line_item])
    if @line_item.save
      flash[:notice] = "New Line Item Created"
      redirect_to @line_item.issue
    else
      flash[:error] = @line_item.errors.full_messages.to_sentence 
      redirect_to new_line_item_path
    end
  end
  
  # display a specific line item
  def show
    begin
      @line_item = LineItem.find_by_id(params[:id])
    rescue ActiveRecord::RecordNotFound
      render_404
    end
  end
  
  # return an HTML form for editing a line item
  def edit
    begin
      @line_item = LineItem.find_by_id(params[:id])
    rescue ActiveRecord::RecordNotFound
      render_404
    end
  end
  
  # update a specific line item
  def update
    begin   
      @line_item = LineItem.find_by_id(params[:id])
      if @line_item.update_attributes(params[:line_item])
        flash[:notice] = "Line Item updated"
        redirect_to @line_item
      else
        flash[:error] = @line_item.errors.full_messages.to_sentence if @line_item.errors
        redirect_to edit_line_item_path
      end
    rescue ActiveRecord::RecordNotFound
      render_404
    end
  end  

  # delete a specific line item
  def destroy
    begin
      line_item = LineItem.find_by_id(params[:id])
      issue = line_item.issue
      line_item.destroy
      flash[:notice] = "Line Item deleted successfully"
      redirect_to issue
    rescue ActiveRecord::RecordNotFound
      render_404
    end
  end

end
