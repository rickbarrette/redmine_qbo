#The MIT License (MIT)
#
#Copyright (c) 2022 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# TODO move this into seperate plugin
class QboHookListener < Redmine::Hook::Listener

  # Check to see if the Invoice custom field VIN matches
  def process_invoice_custom_fields(context = {})
    Rails.logger.debug "QboHookListener.process_invoice_custom_fields"
    issue = context[:issue]
    invoice = context[:invoice]
    is_changed = false

    # update the invoive custom fields with infomation from the issue if available
    invoice.custom_fields.each { |cf|

      # VIN from the attached vehicle
      begin
        if cf.name.eql? "VIN"
          # Only update if blank to prevent infite loops
          # TODO check cf_sync_confict flag once implemented
          if cf.string_value.to_s.blank?
            logger.debug " VIN was blank, updating the invoice vin in quickbooks"
            vin = Vehicle.find(issue.vehicles_id).vin
            break if vin.nil?
            if not cf.string_value.to_s.eql? vin
              cf.string_value = vin.to_s
              logger.debug "VIN has changed"
              is_changed = true
            end

          end
        end
      rescue
        #do nothing
      end
    }

    return { issue: issue, invoice: invoice, is_changed: is_changed } 
  end

  # Add vehicle information to the left side of the pdf attribute block
  def pdf_left(context = {})
    left = []
    issue = context[:issue]
    v = Vehicle.find_by_id(issue.vehicles_id)
    vehicle = v.to_s unless v.nil?
    vin = v.vin.gsub(/(.{9})/, '\1 ') unless v.nil?
    
    left << [l(:field_vehicles), vehicle]
    left << [l(:field_vin), vin]
    return left
  end

  # Add vehicle information to the right side of the pdf attribute block
  def pdf_right(context = {})
    right = []
    issue = context[:issue]
    v = Vehicle.find_by_id(issue.vehicles_id)
    notes = v unless v.nil?
    right << [l(:field_notes), notes]
    return right
  end

end
