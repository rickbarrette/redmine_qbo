#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class Item < QboBaseModel
  belongs_to :account, optional: true
  
  # QuickBooks only requires a name: services such as Labor often have no description or rate
  validates_presence_of :id, :name
  validates :unit_price, numericality: { greater_than_or_equal_to: 0 }

  # QuickBooks item types that can't go on an estimate or invoice line themselves
  UNSELLABLE_TYPES = %w[Category Group].freeze

  # Active products/services that can go on a line (services, non-inventory and inventory items), for the
  # pickers and the labor products/services setting
  scope :sellable, -> { where(active: true).where.not(type: UNSELLABLE_TYPES).or(where(active: true, type: nil)) }
  self.primary_key = :id
  self.inheritance_column = :_type_disabled
  qbo_sync push: true
  after_initialize :set_defaults, if: :new_record?
  before_destroy :make_inactive

  # Updates Both local & remote DB account ref (a blank or unknown account leaves QBO's ref unchanged)
  def account_id=(id)
    account = Account.find_by(id: id) if id.present?
    details.income_account_ref = account.ref if account
    super
  end

  # Updates Both local & remote DB description
  def description=(s)
    details.description = s
    super
  end

  # Updates Both local & remote DB name 
  def name=(s)
    details.name = s
    super
  end

  def make_inactive
    details.active = false
    push_to_qbo
  end

  def set_defaults
    self.taxable = true if taxable.nil?
  end

  # Updates Both local & remote DB sku
  def sku=(s)
    details.sku = s
    super
  end

  # Updates Both local & remote DB type
  def type=(s)
    details.type = s.to_s
    super
  end

   # Updates Both local & remote DB price
  def unit_price=(s)
    details.unit_price = s
    super
  end

end