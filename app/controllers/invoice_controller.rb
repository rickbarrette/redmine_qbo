#The MIT License (MIT)
#
#Copyright (c) 2024 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
class InvoiceController < ApplicationController
  
  include AuthHelper
  
  before_action :require_user, :unless => proc {|c| session[:token].nil? }
  skip_before_action :verify_authenticity_token, :check_if_login_required, :unless => proc {|c| session[:token].nil? }
  
  #
  # Downloads and forwards the invoice pdf
  #
  def show
    begin
      qbo = Qbo.first
        qbo.perform_authenticated_request do |access_token|
        service = Quickbooks::Service::Invoice.new(:company_id => qbo.realm_id, :access_token => access_token)
        invoice = service.fetch_by_id(params[:id])
        @pdf = service.pdf(invoice)
        send_data @pdf, filename: "invoice #{invoice.doc_number}.pdf", :disposition => 'inline', :type => "application/pdf"
      end
    rescue
      redirect_to :back, :flash => { :error => "Invoice not found" }
    end
  end
end
