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
  # What the Refund invoice page posts: the paid invoice, the lines refunded (each with its quantity and
  # amount), whether a restocking fee is charged on the parts among them, how the money goes back (card terminal
  # or company check), and what else to do.
  class InvoiceRefundForm
    include ActiveModel::Model
    include ActiveModel::Validations

    ATTRIBUTES = %i[customer_id invoice_id txn_date method check_number reason charge_fee note_issues
                    email_customer].freeze
    FLAGS = %i[charge_fee note_issues email_customer].freeze

    # One invoice line as posted: refund ticked, the quantity and the amount refunded
    LineChoice = Struct.new(:refund, :quantity, :amount, keyword_init: true) do
      def refund?
        refund.to_s == '1' || refund == true
      end

      def quantity_value
        quantity.blank? ? nil : EstimateForm.decimal(quantity)
      end

      def amount_value
        amount.blank? ? nil : EstimateForm.decimal(amount)
      end
    end

    attr_accessor(*ATTRIBUTES)
    # { line key => LineChoice }
    attr_writer :lines

    validate :validate_refund

    # params: the refund's permitted params, lines as { key => { refund:, quantity:, amount: } }
    def self.from_params(params)
      params = params.to_h.stringify_keys
      form = new(ATTRIBUTES.to_h { |attr| [attr, params[attr.to_s].to_s.strip] })
      form.lines = (params['lines'] || {}).to_h.to_h do |key, line|
        line = line.to_h.stringify_keys
        [key.to_s, LineChoice.new(refund: line['refund'].to_s, quantity: line['quantity'].to_s.strip,
                                  amount: line['amount'].to_s.strip.delete('$,'))]
      end
      form
    end

    def self.permitted
      ATTRIBUTES + [{ lines: {} }]
    end

    def lines
      @lines ||= {}
    end

    def line(key)
      lines[key.to_s]
    end

    def chosen
      lines.select { |_, line| line.refund? }
    end

    def txn_date_value
      EstimateForm.date(txn_date)
    end

    def check?
      method == 'check'
    end

    FLAGS.each do |flag|
      define_method(:"#{flag}?") { send(flag).to_s == '1' || send(flag) == true }
    end

    private

    def validate_refund
      errors.add(:base, I18n.t(:error_estimate_needs_customer)) if customer_id.blank?
      errors.add(:base, I18n.t(:error_refund_no_invoice)) if invoice_id.blank?
      errors.add(:base, I18n.t(:error_refund_method)) unless QboRefund::METHODS.include?(method)
      errors.add(:base, I18n.t(:error_refund_check_number)) if check? && check_number.blank?
      errors.add(:base, I18n.t(:error_refund_reason)) if reason.blank?
      errors.add(:base, I18n.t(:error_estimate_field_invalid, field: I18n.t(:label_refund_date))) if txn_date_value.nil?
      errors.add(:base, I18n.t(:error_refund_no_lines)) if chosen.empty?
    end
  end
end
