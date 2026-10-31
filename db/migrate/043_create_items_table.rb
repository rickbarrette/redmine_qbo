#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# The QuickBooks product/service list. The table was created by redmine_qbo_lineitems before items moved
# into this plugin, so each step is skipped when an existing database already has it: nothing is dropped or
# copied, the existing table is simply used from here on.
class CreateItemsTable < ActiveRecord::Migration[7.0]
  def up
    return if table_exists?(:items)

    create_table :items do |t|
      t.text    :description, null: false
      t.decimal :unit_price,
                precision: 15,
                scale: 4,
                null: false,
                default: 0
      t.boolean :active, default: true, null: false
      t.timestamps
    end
  end

  def down
    drop_table :items if table_exists?(:items)
  end
end
