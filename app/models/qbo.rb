#The MIT License (MIT)
#
#Copyright (c) 2022 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class Qbo < ActiveRecord::Base
  unloadable
    
  include QuickbooksOauth

  # 
  # Get a quickbooks base service object for type
  # @params type of base
  #
  def self.get_base(type)
    # lets getnourbold access token from the database
    oauth2_client = construct_oauth2_client
    qbo = self.first

    qbo.perform_authenticated_request do |access_token|   
      # build the reqiested service
      case type
        when :time_activity
          return Quickbooks::Service::TimeActivity.new(:company_id => qbo.company_id, :access_token => access_token)
        when :customer
          return Quickbooks::Service::Customer.new(:company_id => qbo.company_id, :access_token => access_token)
        when :invoice
          return Quickbooks::Service::Invoice.new(:company_id => qbo.company_id, :access_token => access_token)
        when :estimate
          return Quickbooks::Service::Estimate.new(:company_id => qbo.company_id, :access_token => access_token)
        when :employee
          return Quickbooks::Service::Employee.new(:company_id => qbo.company_id, :access_token => access_token)
      else
        return access_token
      end
    end
   
  end
  
  # Updates last sync time stamp
  def self.update_time_stamp
    date = DateTime.now
    logger.info "Updating QBO timestamp to #{date}"
    qbo = Qbo.first
    qbo.last_sync = date
    qbo.save
  end
  
  def self.last_sync
    format_time(Qbo.first.last_sync)
  end
end
