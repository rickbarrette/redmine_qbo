#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class QboSyncJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: 5.minutes, attempts: 5

  # Perform a full sync of all records for the entity, or an incremental sync of only those updated since the last sync
  def perform(full_sync: false, id: nil, entity: nil, doc_number: nil)
    raise "An entity to sync is required" unless entity
    @entity = entity
    qbo = QboConnectionService.current!
    raise "No QBO configuration found" unless qbo

    log "Starting #{full_sync ? 'full' : 'incremental'} sync for #{entity} ##{id || doc_number || 'all'}..."
    service = "#{entity}SyncService".constantize.new(qbo: qbo)

    if id.present?
      service.sync_by_id(id)
    elsif doc_number.present?
      service.sync_by_doc_number(doc_number)
    else
      service.sync(full_sync: full_sync)
    end
  end

  private

  # Log messages with the entity type for better traceability
  def log(msg)
    Rails.logger.info "[#{@entity}SyncJob] #{msg}"
  end
end