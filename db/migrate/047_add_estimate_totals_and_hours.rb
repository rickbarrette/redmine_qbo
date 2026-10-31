#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


# Cached report figures: each estimate's total, and the man-hours on estimates and invoices (quantities of the
# products/services set as "Replaced by imported time"). Filled in by the sync and the webhook.
class AddEstimateTotalsAndHours < ActiveRecord::Migration[7.0]
  def up
    add_column :estimates, :total_amount, :decimal, precision: 15, scale: 2 unless column_exists?(:estimates, :total_amount)
    add_column :estimates, :hours, :float unless column_exists?(:estimates, :hours)
    add_column :invoices, :hours, :float unless column_exists?(:invoices, :hours)
    add_index :estimates, :txn_date unless index_exists?(:estimates, :txn_date)
    add_index :invoices, :txn_date unless index_exists?(:invoices, :txn_date)
  end

  def down
    remove_index :invoices, :txn_date if index_exists?(:invoices, :txn_date)
    remove_index :estimates, :txn_date if index_exists?(:estimates, :txn_date)
    remove_column :invoices, :hours if column_exists?(:invoices, :hours)
    remove_column :estimates, :hours if column_exists?(:estimates, :hours)
    remove_column :estimates, :total_amount if column_exists?(:estimates, :total_amount)
  end
end
