#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Estimate and invoice drafts: what's filled in on the editor, kept in Redmine until it's saved to QuickBooks
class CreateQboDrafts < ActiveRecord::Migration[7.0]
  def up
    return if table_exists?(:qbo_drafts)

    create_table :qbo_drafts do |t|
      t.string :document, null: false, limit: 20
      t.bigint :customer_id
      # Who saved it last
      t.integer :user_id
      # The editor's fields, as posted (JSON)
      t.text :data, size: :medium
      t.timestamps
    end
    add_index :qbo_drafts, [:document, :customer_id]
  end

  def down
    drop_table :qbo_drafts if table_exists?(:qbo_drafts)
  end
end
