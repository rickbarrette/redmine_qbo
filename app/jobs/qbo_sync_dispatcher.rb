#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class QboSyncDispatcher

  SYNC_JOBS = [
    Customer,
    Estimate,
    Invoice,
    Employee
  ].freeze

  # Dispatches all synchronization jobs to perform a full sync of QuickBooks entities with the local database. 
  # Each job is enqueued with the `full_sync` flag set to true.
  def self.sync!(full_sync: false)
    log "Manual Sync initated for #{full_sync ? "full sync" : "incremental sync"}"
    enque_jobs full_sync: full_sync
  end

  private

  # Dynamically enques all sync jobs
  def self.enque_jobs(full_sync: full_sync)
    jobs = SYNC_JOBS.dup

    # Allow other plugins to add addtional sync jobs via Hooks
    Redmine::Hook.call_hook( :qbo_full_sync ).each do |context|
        next unless context
        jobs.push context
        log "Added additionals QBO Sync Job for #{context.to_s}"
    end

    jobs.each { |job| QboSyncJob.perform_later(entity: job, full_sync: full_sync) }
  end

  def self.log(msg)
    Rails.logger.info "[QboSyncDispatcher] #{msg}"
  end
  
end