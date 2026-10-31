#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class ItemSyncService < SyncServiceBase

  private

  # Specify the local model this service syncs
  def self.model_class
    Item
  end

  # Specify a page size of 20, as the API only returns 20 items at a time.
  def self.page_size
    20
  end

  map_attribute :active, :active?
  map_attribute :taxable, :taxable?
  # Items without an income account (e.g. categories), or whose account hasn't synced yet, get none
  # instead of failing the whole sync; the next sync fills it in.
  map_attribute :account do |remote|
    account_id = remote.income_account_ref&.value
    account_id.present? ? Account.find_by(id: account_id.to_i) : nil
  end
  map_attributes :id, :name, :sku, :type
  # Services such as Labor often have no description or rate in QuickBooks; they sync as blank and 0
  # instead of failing validation and being skipped
  map_attribute(:description) { |remote| remote.description.to_s }
  map_attribute(:unit_price) { |remote| remote.unit_price || 0 }

end