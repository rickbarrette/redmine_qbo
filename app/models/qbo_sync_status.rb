#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


# A QuickBooks sync that's queued or running, one row per entity (Invoice, Estimate...), with how many records
# it has processed so far. The row is removed when the sync finishes. Rows not touched for STALE are ignored,
# so a sync that died (e.g. Redmine restarted mid-sync) doesn't leave a notice up forever.
class QboSyncStatus < ActiveRecord::Base
  STALE = 6.hours

  scope :active, -> { where('updated_at > ?', STALE.ago) }

  # A sync was asked for and is waiting for the job to start
  def self.queued(entity)
    record(entity) { |s| s.state = 'queued' unless s.state == 'running' }
  end

  # The sync started
  def self.running(entity)
    record(entity) do |s|
      s.state = 'running'
      s.processed = 0
      s.started_at = Time.now
    end
  end

  # count more records were processed
  def self.progress(entity, count)
    where(entity: entity.to_s).update_all(['processed = processed + ?, updated_at = ?', count.to_i, Time.now])
  rescue StandardError => e
    Rails.logger.warn "[QboSyncStatus] #{e.message}"
  end

  def self.finished(entity)
    where(entity: entity.to_s).delete_all
  rescue StandardError => e
    Rails.logger.warn "[QboSyncStatus] #{e.message}"
  end

  # Active syncs by entity name: { "Invoice" => QboSyncStatus, ... }, optionally only for some entities
  def self.by_entity(entities = nil)
    scope = active
    scope = scope.where(entity: Array(entities).map(&:to_s)) if entities
    scope.index_by(&:entity)
  rescue StandardError
    {}
  end

  def self.record(entity)
    status = find_or_initialize_by(entity: entity.to_s)
    status.state ||= 'queued'
    yield status
    status.updated_at = Time.now
    status.save!
  rescue StandardError => e
    Rails.logger.warn "[QboSyncStatus] #{e.message}"
  end
  private_class_method :record

  def running?
    state == 'running'
  end
end
