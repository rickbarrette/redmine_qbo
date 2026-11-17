#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Customer refunds (SOP-OPS-014): the restocking fee invoice, the refund check or card refund, and what was
# done in QuickBooks and Redmine, so a refund can be looked up (and finished by hand if a step failed)
class CreateQboRefunds < ActiveRecord::Migration[7.0]
  def up
    return if table_exists?(:qbo_refunds)

    create_table :qbo_refunds do |t|
      t.bigint :customer_id, null: false
      # The canceled order's estimate, if any
      t.bigint :estimate_id
      t.string :estimate_number
      t.integer :user_id
      t.date :txn_date
      # check or card
      t.string :method, null: false, limit: 10
      t.string :check_number
      t.text :reason
      t.decimal :parts_amount, precision: 15, scale: 2, null: false, default: 0
      t.decimal :fee_rate, precision: 6, scale: 2, null: false, default: 0
      t.decimal :fee_amount, precision: 15, scale: 2, null: false, default: 0
      # The customer's credit before the refund, and what was refunded
      t.decimal :credit_amount, precision: 15, scale: 2, null: false, default: 0
      t.decimal :refund_amount, precision: 15, scale: 2, null: false, default: 0
      # The QuickBooks fee invoice and the refund check or expense
      t.string :fee_invoice_id
      t.string :fee_invoice_number
      t.string :purchase_id
      # The customer's QuickBooks balance afterwards
      t.decimal :balance_after, precision: 15, scale: 2
      t.boolean :estimate_closed, null: false, default: false
      # The work orders set to canceled (JSON list of issue ids)
      t.text :canceled_issue_ids
      t.string :emailed_to
      # done, or incomplete (a step failed: message says which)
      t.string :status, null: false, default: 'incomplete', limit: 20
      t.text :message
      t.timestamps
    end
    add_index :qbo_refunds, :customer_id
  end

  def down
    drop_table :qbo_refunds if table_exists?(:qbo_refunds)
  end
end
