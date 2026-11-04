#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class Invoice < QboBaseModel

  has_and_belongs_to_many :issues
  belongs_to :customer
  validates :id, presence: true, uniqueness: true
  validates :doc_number, :txn_date, presence: true
  self.primary_key = :id
  qbo_sync push: false

  include QboActivity
  qbo_activity 'qbo_invoices', icon: 'qbo-invoice', permissions: %i[view_customers write_invoices],
               title: ->(i) { I18n.t(:label_activity_invoice, number: i.doc_number, customer: i.activity_customer) },
               description: ->(i) { i.activity_description },
               url: ->(i) { { controller: 'invoices', action: 'show', id: i.id } }

  # Return the invoice's document number as its string representation
  def to_s
    doc_number
  end

  # Amount and where it stands, e.g. "$1,250.00 · Partially paid ($400.00 owed)"
  def activity_description
    state = status
    owed = activity_money(self[:balance]) if state && self[:balance].to_d.positive?
    [activity_money(self[:total_amount]),
     (I18n.t(:"label_invoice_status_#{state}", default: state.to_s.humanize) if state),
     (I18n.t(:text_activity_invoice_owed, amount: owed) if owed && state != :open && state != :overdue)].compact.join(' · ')
  end

  # Paid, partially paid, overdue, open or voided, from the cached total, balance and due date
  # (RedmineQboBilling::InvoiceStatus); nil when the balance isn't cached
  def status(today: User.current.today)
    RedmineQboBilling::InvoiceStatus.status(total: self[:total_amount], balance: self[:balance],
                                            due_date: self[:due_date], today: today)
  end

end