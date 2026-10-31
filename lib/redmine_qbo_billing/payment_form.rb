#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module RedmineQboBilling
  # What the Receive payment page posts: who paid, how, and how much. PaymentWriter turns it into a
  # QuickBooks payment, applied to the customer's oldest open invoices first, or kept as a deposit.
  class PaymentForm
    include ActiveModel::Model
    include ActiveModel::Validations

    ATTRIBUTES = %i[customer_id customer_name txn_date payment_method_id reference amount deposit memo].freeze

    attr_accessor(*ATTRIBUTES)
    # Invoices ticked on the page: the payment goes on these (oldest first). None ticked: all open invoices.
    attr_accessor :invoice_ids

    validate :validate_payment

    def self.from_params(params)
      params = params.to_h.stringify_keys
      new(ATTRIBUTES.to_h { |attr| [attr, params[attr.to_s].to_s.strip] }).tap do |form|
        form.invoice_ids = Array(params['invoice_ids']).map(&:to_s).reject(&:blank?).uniq
      end
    end

    def initialize(attributes = {})
      super
      self.invoice_ids ||= []
    end

    def amount_value
      EstimateForm.decimal(amount)
    end

    def txn_date_value
      EstimateForm.date(txn_date)
    end

    # A deposit is kept unapplied (credit on the customer's account) instead of paying invoices
    def deposit?
      deposit == true || deposit.to_s == '1'
    end

    private

    def validate_payment
      errors.add(:base, I18n.t(:error_estimate_needs_customer)) if customer_id.blank?
      errors.add(:base, I18n.t(:error_payment_needs_method)) if payment_method_id.blank?
      value = amount_value
      errors.add(:base, I18n.t(:error_payment_amount)) if value.nil? || value <= 0
      errors.add(:base, I18n.t(:error_estimate_field_invalid, field: I18n.t(:label_payment_date))) if txn_date_value.nil?
    end
  end
end
