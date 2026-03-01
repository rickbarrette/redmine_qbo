#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class InvoiceSyncService < SyncServiceBase
  
  private

  # Specify the local model this service syncs
  def self.model_class
    Invoice
  end
  
  # Map relevant attributes from the QBO Invoice to the local Invoice model
  def process_attributes(local, remote)
    local.doc_number      = remote.doc_number
    local.txn_date        = remote.txn_date
    local.due_date        = remote.due_date
    local.total_amount    = remote.total
    local.balance         = remote.balance
    local.qbo_updated_at  = remote.meta_data&.last_updated_time
    local.customer = Customer.find_by(id: remote.customer_ref&.value)
  end

  # Attach QBO Invoices to the local Issues
  def attach_documents(local, remote)
    InvoiceAttachmentService.new(local, remote).attach
  end
end