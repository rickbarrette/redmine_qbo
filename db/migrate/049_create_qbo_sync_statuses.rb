#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


# Which QuickBooks syncs are queued or running, and how far along they are (shown on the business report and
# the settings page while a long sync runs)
class CreateQboSyncStatuses < ActiveRecord::Migration[7.0]
  def up
    return if table_exists?(:qbo_sync_statuses)

    create_table :qbo_sync_statuses do |t|
      t.string   :entity, null: false
      t.string   :state, null: false
      t.integer  :processed, null: false, default: 0
      t.datetime :started_at
      t.timestamps
    end
    add_index :qbo_sync_statuses, :entity, unique: true
  end

  def down
    drop_table :qbo_sync_statuses if table_exists?(:qbo_sync_statuses)
  end
end
