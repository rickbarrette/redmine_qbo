#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class EmployeeSyncService
  PAGE_SIZE = 1000

  def initialize(qbo:)
    @qbo = qbo
  end

  # Sync all employees, or only those updated since the last sync
  def sync(full_sync: false)
    log "Starting #{full_sync ? 'full' : 'incremental'} employee sync"

    @qbo.perform_authenticated_request do |access_token|
      service = Quickbooks::Service::Employee.new(company_id: @qbo.realm_id, access_token: access_token)

      page = 1
      loop do
        collection = fetch_page(service, page, full_sync)
        entries = Array(collection&.entries)
        break if entries.empty?

        entries.each { |remote| persist(remote) }

        break if entries.size < PAGE_SIZE
        page += 1
      end
    end

    log "Employee sync complete"
  end

  # Sync a single employee by its QBO ID, used for webhook updates
  def sync_by_id(id)
    @qbo.perform_authenticated_request do |access_token|
      service = Quickbooks::Service::Employee.new(company_id: @qbo.realm_id, access_token: access_token)
      remote = service.fetch_by_id(id)
      persist(remote)
    end
  end

  private

  # Fetch a page of employees, either all or only those updated since the last sync
  def fetch_page(service, page, full_sync)
    start_position = (page - 1) * PAGE_SIZE + 1

    if full_sync
      service.query("SELECT * FROM Employee STARTPOSITION #{start_position} MAXRESULTS #{PAGE_SIZE}")
    else
      last_update = Employee.maximum(:qbo_updated_at) || 1.year.ago
      service.query(<<~SQL.squish)
        SELECT * FROM Employee
        WHERE MetaData.LastUpdatedTime > '#{last_update.utc.iso8601}'
        STARTPOSITION #{start_position}
        MAXRESULTS #{PAGE_SIZE}
      SQL
    end
  end

  # Create or update a local Employee record based on the QBO remote data
  def persist(remote)
    employee = Employee.find_or_initialize_by(id: remote.id)

    if remote.active?
      employee.name = remote.display_name

      if employee.changed?
        employee.save
        log "Updated employee #{remote.id}"
      end
    else
      if employee.persisted?
        employee.destroy
        log "Deleted employee #{remote.id}"
      end
    end
  rescue => e
    log "Failed to sync employee #{remote.id}: #{e.message}"
  end

  def log(msg)
    Rails.logger.info "[EmployeeSyncService] #{msg}"
  end
end