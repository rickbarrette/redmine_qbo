#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class Employee < ActiveRecord::Base
  
  include Redmine::I18n

  has_many :users
  validates_presence_of :id, :name

  self.primary_key = :id

  # Returns the last sync time formatted for display. If no sync has occurred, returns a default message.
  def self.last_sync
    return I18n.t(:label_qbo_never_synced) unless maximum(:updated_at)
    format_time(maximum(:updated_at))
  end
  
  # Sync all employees, typically triggered by a scheduled task or manual sync request
  def self.sync
    EmployeeSyncJob.perform_later(full_sync: true)
  end

  # Sync a single employee by ID, typically triggered by a webhook notification or manual sync request
  def self.sync_by_id(id)
    EmployeeSyncJob.perform_later(id: id)
  end
  
end
