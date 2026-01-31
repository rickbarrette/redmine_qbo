#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
class EstimateController < ApplicationController
  
  include AuthHelper
  
  before_action :require_user, unless: proc {|c| session[:token].nil? }
  skip_before_action :verify_authenticity_token, :check_if_login_required, unless: proc {|c| session[:token].nil? }

  def get_estimate
    # Force sync for estimate by doc number if not found
    if  Estimate.find_by_doc_number(params[:search]).nil?
      begin
        Estimate.sync_by_doc_number(params[:search]) if params[:search]
      rescue
        logger.info "Estimate.find_by_doc_number failed"
      end
    end

    estimate = Estimate.find_by_id(params[:id]) if params[:id]
    estimate = Estimate.find_by_doc_number(params[:search]) if params[:search]
    return estimate
  end
  
  #
  # Downloads and forwards the estimate pdf
  #
  def show
    estimate = get_estimate

    begin
      send_data estimate.pdf, filename: "estimate #{estimate.doc_number}.pdf", disposition: :inline, type: "application/pdf"
    rescue
      redirect_to :back, flash: { error: I18n.t(:notice_estimate_not_found) }
    end
  end

  #
  # Downloads estimate by document number
  #
  def doc
    estimate = get_estimate
    
    begin
      send_data estimate.pdf, filename: "estimate #{estimate.doc_number}.pdf", disposition: :inline, type: "application/pdf"
    rescue
      redirect_to :back, flash: { error: I18n.t(:notice_estimate_not_found) }
    end
  end

end
