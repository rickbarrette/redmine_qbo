#The MIT License (MIT)
#
#Copyright (c) 2022 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class AddTxnDates < ActiveRecord::Migration[5.1]
  def change
    add_column :qbo_invoices, :txn_date, :date
    add_column :qbo_estimates, :txn_date, :date

    reversible do |direction|
      direction.up {
        break unless Qbo.first

        QboEstimate.reset_column_information
        QboInvoice.reset_column_information

        say "Sync Estimates"

        QboEstimate.sync

        say "Sync Invoices"

        invoices = QboInvoice.get_base.all

        invoices.each { |invoice|
            # Load the invoice into the database
            qbo_invoice = QboInvoice.find_or_create_by(id: invoice.id)
            qbo_invoice.doc_number = invoice.doc_number
            qbo_invoice.id = invoice.id
            qbo_invoice.customer_id = invoice.customer_ref
            qbo_invoice.txn_date = invoice.txn_date
            qbo_invoice.save!
        }
      }
    end
  end

end
