#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


# Caches QuickBooks payments: customer, date, amount and what's still unapplied
class PaymentSyncService < SyncServiceBase

  private

  # Specify the local model this service syncs
  def self.model_class
    Payment
  end

  map_attributes :txn_date
  map_attribute :total_amount, :total
  map_attribute :unapplied_amount
  map_attribute :qbo_updated_at, "meta_data.last_updated_time"
  # A payment whose customer hasn't synced yet keeps none until the next sync
  map_attribute :customer do |remote|
    id = remote.customer_ref&.value
    id.present? ? Customer.find_by(id: id) : nil
  end

end
