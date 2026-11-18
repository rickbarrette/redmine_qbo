#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Refunds of paid invoices (completed, billed and paid-in-full work): a QuickBooks Refund Receipt for the lines
# refunded, with an optional restocking fee, alongside the refunds of customer credit (canceled orders)
class AddInvoiceRefunds < ActiveRecord::Migration[7.0]
  def up
    # credit: a canceled order's deposit (fee invoice + check/expense); invoice: a paid invoice (refund receipt)
    add_column :qbo_refunds, :kind, :string, null: false, default: 'credit', limit: 10 unless column_exists?(:qbo_refunds, :kind)
    add_column :qbo_refunds, :invoice_id, :bigint unless column_exists?(:qbo_refunds, :invoice_id)
    add_column :qbo_refunds, :invoice_number, :string unless column_exists?(:qbo_refunds, :invoice_number)
    # The Refund Receipt's number (its id is purchase_id)
    add_column :qbo_refunds, :receipt_number, :string unless column_exists?(:qbo_refunds, :receipt_number)
    # The refunded lines before the discount, fee and tax; the invoice discount's share; the tax refunded
    add_column :qbo_refunds, :lines_amount, :decimal, precision: 15, scale: 2, null: false, default: 0 unless column_exists?(:qbo_refunds, :lines_amount)
    add_column :qbo_refunds, :discount_amount, :decimal, precision: 15, scale: 2, null: false, default: 0 unless column_exists?(:qbo_refunds, :discount_amount)
    add_column :qbo_refunds, :tax_amount, :decimal, precision: 15, scale: 2, null: false, default: 0 unless column_exists?(:qbo_refunds, :tax_amount)
    # The lines refunded (JSON: key, description, quantity, amount, parts), so a line isn't refunded twice
    add_column :qbo_refunds, :refunded_lines, :text unless column_exists?(:qbo_refunds, :refunded_lines)
    # The work orders the refund was noted on (JSON list of issue ids)
    add_column :qbo_refunds, :noted_issue_ids, :text unless column_exists?(:qbo_refunds, :noted_issue_ids)
    add_index :qbo_refunds, :invoice_id unless index_exists?(:qbo_refunds, :invoice_id)
  end

  def down
    remove_index :qbo_refunds, :invoice_id if index_exists?(:qbo_refunds, :invoice_id)
    %i[kind invoice_id invoice_number receipt_number lines_amount discount_amount tax_amount refunded_lines
       noted_issue_ids].each do |column|
      remove_column :qbo_refunds, column if column_exists?(:qbo_refunds, column)
    end
  end
end
