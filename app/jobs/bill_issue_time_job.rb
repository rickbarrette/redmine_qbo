#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class BillIssueTimeJob < ActiveJob::Base
  queue_as :default

  def perform(issue_id)
    issue = Issue.find(issue_id)

    Rails.logger.debug "QBO: Starting billing for issue ##{issue.id}"

    issue.with_lock do
      unbilled_entries = issue.time_entries.where(billed: [false, nil]).lock

      return if unbilled_entries.blank?

      totals = aggregate_hours(unbilled_entries)
      return if totals.blank?

      qbo = Qbo.first
      raise "No QBO configuration found" unless qbo

      qbo.perform_authenticated_request do |access_token|
        create_time_activities(issue, totals, access_token, qbo)
      end

      # Only mark billed AFTER successful QBO creation
      unbilled_entries.update_all(billed: true)
    end

    Rails.logger.debug "QBO: Completed billing for issue ##{issue.id}"
  rescue => e
    Rails.logger.error "QBO: Billing failed for issue ##{issue_id} - #{e.message}"
    raise e
  end

  private

  def aggregate_hours(entries)
    entries.includes(:activity)
           .group_by { |e| e.activity&.name }
           .transform_values { |rows| rows.sum(&:hours) }
           .compact
  end

  def create_time_activities(issue, totals, access_token, qbo)
    time_service = Quickbooks::Service::TimeActivity.new(
      company_id: qbo.realm_id,
      access_token: access_token
    )

    item_service = Quickbooks::Service::Item.new(
      company_id: qbo.realm_id,
      access_token: access_token
    )

    totals.each do |activity_name, hours_float|
      next if activity_name.blank?
      next if hours_float.to_f <= 0

      item = find_item(item_service, activity_name)
      next unless item

      hours, minutes = convert_hours(hours_float)

      time_entry = Quickbooks::Model::TimeActivity.new
      time_entry.description     = build_description(issue)
      time_entry.employee_id     = issue.assigned_to.employee_id
      time_entry.customer_id     = issue.customer_id
      time_entry.billable_status = "Billable"
      time_entry.hours           = hours
      time_entry.minutes         = minutes
      time_entry.name_of         = "Employee"
      time_entry.txn_date        = Date.today
      time_entry.hourly_rate     = item.unit_price
      time_entry.item_id         = item.id

      Rails.logger.debug "QBO: Creating TimeActivity for #{activity_name} (#{hours}h #{minutes}m)"

      time_service.create(time_entry)
    end
  end

  def convert_hours(hours_float)
    total_minutes = (hours_float.to_f * 60).round
    hours = total_minutes / 60
    minutes = total_minutes % 60
    [hours, minutes]
  end

  def build_description(issue)
    base = "#{issue.tracker} ##{issue.id}: #{issue.subject}"
    return base if issue.closed?
    "#{base} (Partial @ #{issue.done_ratio}%)"
  end

  def find_item(item_service, name)
    safe = name.gsub("'", "\\\\'")
    item_service.query("SELECT * FROM Item WHERE Name = '#{safe}'").first
  end
end