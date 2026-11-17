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
  # What the Refund page posts (SOP-OPS-014): the canceled order's estimate, the parts the restocking fee is
  # worked out on, how the money goes back (card terminal or company check), and what else to do in
  # QuickBooks and Redmine.
  class RefundForm
    include ActiveModel::Model
    include ActiveModel::Validations

    ATTRIBUTES = %i[customer_id estimate_id txn_date parts_amount method check_number reason
                    close_estimate cancel_issues email_customer].freeze

    attr_accessor(*ATTRIBUTES)

    validate :validate_refund

    def self.from_params(params)
      params = params.to_h.stringify_keys
      new(ATTRIBUTES.to_h { |attr| [attr, params[attr.to_s].to_s.strip] })
    end

    def parts_value
      parts_amount.blank? ? BigDecimal('0') : EstimateForm.decimal(parts_amount)
    end

    def txn_date_value
      EstimateForm.date(txn_date)
    end

    def check?
      method == 'check'
    end

    %i[close_estimate cancel_issues email_customer].each do |flag|
      define_method(:"#{flag}?") { send(flag).to_s == '1' || send(flag) == true }
    end

    private

    def validate_refund
      errors.add(:base, I18n.t(:error_estimate_needs_customer)) if customer_id.blank?
      errors.add(:base, I18n.t(:error_refund_method)) unless QboRefund::METHODS.include?(method)
      errors.add(:base, I18n.t(:error_refund_check_number)) if check? && check_number.blank?
      errors.add(:base, I18n.t(:error_refund_reason)) if reason.blank?
      value = parts_value
      errors.add(:base, I18n.t(:error_refund_parts_amount)) if value.nil? || value.negative?
      errors.add(:base, I18n.t(:error_estimate_field_invalid, field: I18n.t(:label_refund_date))) if txn_date_value.nil?
    end
  end
end
