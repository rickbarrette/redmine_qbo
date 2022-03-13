#The MIT License (MIT)
#
#Copyright (c) 2022 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
class EstimateController < ApplicationController
  unloadable
  
  include AuthHelper
  
  before_action :require_user, :unless => proc {|c| session[:token].nil? }
  skip_before_action :verify_authenticity_token, :check_if_login_required, :unless => proc {|c| session[:token].nil? }
  
  #
  # Downloads and forwards the estimate pdf
  #
  def show
    e = Estimate.find_by_id(params[:id]) if params[:id]
    e = Estimate.find_by_doc_number(params[:search]) if params[:search]

    begin
      send_data e.pdf, filename: "estimate #{e.doc_number}.pdf", :disposition => 'inline', :type => "application/pdf"
    rescue
      redirect_to :back, :flash => { :error => "Estimate not found" }
    end
  end

  #
  # Downloads estimate by document number
  #
  def doc
    e = Estimate.find_by_doc_number(params[:id]) if params[:id]
    e = Estimate.find_by_doc_number(params[:search]) if params[:search]
    
    begin
      send_data e.pdf, filename: "estimate #{e.doc_number}.pdf", :disposition => 'inline', :type => "application/pdf"
    rescue
      redirect_to :back, :flash => { :error => "Estimate not found" }
    end
  end

end
