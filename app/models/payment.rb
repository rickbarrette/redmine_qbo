#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


# A customer payment, cached from QuickBooks for reporting: id, customer, date and amount. Kept current by the
# webhook and the sync; payments are received through the Receive payment page (RedmineQboBilling::PaymentWriter).
class Payment < QboBaseModel

  belongs_to :customer, optional: true
  validates :id, presence: true, uniqueness: true
  self.primary_key = :id
  qbo_sync push: false

  include QboActivity
  qbo_activity 'qbo_payments', icon: 'qbo-payment', permissions: %i[view_payments receive_payments],
               title: ->(p) { I18n.t(:label_activity_payment, customer: p.activity_customer, amount: p.activity_money(p.total_amount)) },
               description: ->(p) { p.activity_description },
               url: ->(p) { { controller: 'qbo_payments', action: 'show', id: p.id } }

  # Money not yet applied to an invoice, when there is some
  def activity_description
    return '' unless unapplied_amount.to_d.positive?

    I18n.t(:text_activity_payment_unapplied, amount: activity_money(unapplied_amount))
  end

  def to_s
    "#{txn_date} #{total_amount}"
  end

end
