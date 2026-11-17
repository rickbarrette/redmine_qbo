#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# An invoice's sales tax and the day it was paid in full, cached like its total and balance, so reports (e.g.
# redmine_qbo_commission's monthly paid sales) don't have to read invoices from QuickBooks. A full invoice sync
# fills them in for invoices synced before.
class AddInvoiceTaxAndPaidOn < ActiveRecord::Migration[7.0]
  def change
    add_column :invoices, :tax_amount, :decimal, precision: 15, scale: 2 unless column_exists?(:invoices, :tax_amount)
    add_column :invoices, :paid_on, :date unless column_exists?(:invoices, :paid_on)
    add_index :invoices, :paid_on unless index_exists?(:invoices, :paid_on)
  end
end
