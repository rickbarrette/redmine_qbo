#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class WebhookProcessJob < ActiveJob::Base
  queue_as :default

  ALLOWED_ENTITIES = %w[
    Customer
    Invoice
    Estimate
  ].freeze

  # Process incoming QBO webhook notifications and sync relevant data to Redmine
  def perform(raw_body)
    log "Received webhook: #{raw_body}"
    data = JSON.parse(raw_body)

    data.fetch('eventNotifications', []).each do |notification|
      entities = notification.dig('dataChangeEvent', 'entities') || []

      entities.each do |entity|
        process_entity(entity)
      end
    end

    Qbo.update_time_stamp
  end

  private

  # Process a single entity from the webhook payload and sync it to Redmine if it's an allowed type
  def process_entity(entity)
    log "Processing entity: #{entity}"
    name = entity['name']
    id   = entity['id']&.to_i

    return unless ALLOWED_ENTITIES.include?(name)

    model = name.safe_constantize
    return unless model

    if entity['deletedId']
      model.destroy(entity['deletedId'])
      return
    end

    if entity['operation'] == "Delete"
      model.destroy(id)
    else
      model.sync_by_id(id)
    end
  rescue => e
    log "#{e.message}"
  end

  def log(msg)
    Rails.logger.info "[WebhookProcessJob] #{msg}"
  end
end