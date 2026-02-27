#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class CustomerSyncJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: 5.minutes, attempts: 5

  def perform(full_sync: false)
    qbo = Qbo.first
    return unless qbo

    logger.info "[CustomerSyncJob] Starting #{full_sync ? 'full' : 'incremental'} sync..."

    qbo = Qbo.first
    qbo.perform_authenticated_request do |access_token|
            
        service = Quickbooks::Service::Customer.new(company_id: qbo.realm_id, access_token: access_token)

        page = 1
        loop do
          collection = fetch_customers(service, page, full_sync)
          entries = Array(collection&.entries)

          break if entries.empty?

          entries.each { |c| sync_customer(c) }

          page += 1
          break if entries.size < 1000
        end

        logger.info "[CustomerSyncJob] Completed sync."
    end
  rescue => e
    logger.error "[CustomerSyncJob] Fatal error: #{e.message}"
    logger.error e.backtrace.join("\n")
    raise # allows retry
  end

  private

  # Fetch either all or incremental customers
  def fetch_customers(service, page, full_sync)
    start_position = (page - 1) * 1000 + 1

    if full_sync
      service.query("SELECT * FROM Customer STARTPOSITION #{start_position} MAXRESULTS 1000")
    else
      last_update = Customer.maximum(:updated_at) || 1.year.ago
      service.query(<<~SQL.squish)
        SELECT * FROM Customer
        WHERE MetaData.LastUpdatedTime > '#{last_update.utc.iso8601}'
        STARTPOSITION #{start_position}
        MAXRESULTS 1000
      SQL
    end
  rescue => e
    logger.error "[CustomerSyncJob] Failed to fetch page #{page}: #{e.message}"
    nil
  end

  # Sync a single customer record
  def sync_customer(c)
    logger.info "[CustomerSyncJob] Processing customer #{c.id} / #{c.display_name} (active=#{c.active?})"

    customer = Customer.find_or_initialize_by(id: c.id)

    if c.active?
      customer.name = c.display_name
      customer.phone_number = c.primary_phone&.free_form_number&.gsub(/\D/, '')
      customer.mobile_phone_number = c.mobile_phone&.free_form_number&.gsub(/\D/, '')

      if customer.changed?
        customer.save_without_push
        logger.info "[CustomerSyncJob] Updated customer #{c.id}"
      end
    else
      if customer.persisted? && customer.active?
        customer.destroy
        logger.info "[CustomerSyncJob] Deleted customer #{c.id}"
      end
    end
  rescue => e
    logger.error "[CustomerSyncJob] Failed to sync customer #{c.id}: #{e.message}"
  end
end