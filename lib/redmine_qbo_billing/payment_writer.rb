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
  # Receives customer payments in QuickBooks: payment type and amount, applied to the customer's open
  # invoices oldest first (the way QuickBooks applies them on its own screen), or only to the invoices ticked
  # on the page, or saved unapplied as a deposit. Whatever doesn't fit stays unapplied as a credit.
  module PaymentWriter
    Error = EstimateWriter::Error

    METHODS_CACHE_KEY = 'redmine_qbo_billing:payment_methods'

    module_function

    def new_form(customer: nil, user: User.current)
      PaymentForm.new(customer_id: customer&.id, customer_name: customer&.name, txn_date: user.today.iso8601)
    end

    # QuickBooks' payment methods (Cash, Check, Credit Card...), cached for an hour: [[name, id], ...]
    def payment_methods
      cached = Rails.cache.read(METHODS_CACHE_KEY)
      return cached if cached

      methods = with_service('PaymentMethod') { |service| service.query.entries }
      list = Array(methods).select { |m| m.active? != false && m.active? != 'false' }
                           .map { |m| [m.name.to_s, m.id.to_s] }
                           .sort_by { |name, _| name.downcase }
      Rails.cache.write(METHODS_CACHE_KEY, list, expires_in: 1.hour) if list.any?
      list
    rescue StandardError => e
      Rails.logger.warn "[RedmineQboBilling] Could not read payment methods: #{e.message}"
      []
    end

    # The customer's invoices with a balance, oldest first (by date, then number)
    def open_invoices(customer)
      invoices = with_service('Invoice') do |service|
        service.query("SELECT * FROM Invoice WHERE CustomerRef = '#{customer.id.to_i}' ORDERBY TxnDate", per_page: 1000).entries
      end

      Array(invoices).select { |i| BigDecimal(i.balance.to_s.presence || '0') > 0 }
                     .sort_by { |i| [i.txn_date || Date.new(1900), i.doc_number.to_s.rjust(12, '0')] }
                     .map do |i|
        { id: i.id.to_s, doc_number: i.doc_number.to_s, date: i.txn_date.to_s, due_date: i.due_date.to_s,
          total: i.total.to_s, balance: BigDecimal(i.balance.to_s).to_s('F') }
      end
    end

    # Spreads the amount over the invoices in order: [[invoice, applied], ...] and what's left over
    def allocate(amount, invoices)
      left = BigDecimal(amount.to_s)
      applied = []
      invoices.each do |invoice|
        break if left <= 0
        take = [left, BigDecimal(invoice[:balance].to_s)].min
        next if take <= 0
        applied << [invoice, take]
        left -= take
      end
      [applied, left]
    end

    # Creates the payment in QuickBooks and returns it. Open invoices are read again here, so the payment
    # goes on what's open right now.
    def save(form)
      customer = Customer.find_by(id: form.customer_id)
      raise Error, I18n.t(:error_estimate_needs_customer) unless customer

      amount = form.amount_value.round(2)
      applied =
        if form.deposit?
          []
        else
          invoices = open_invoices(customer)
          invoices = invoices.select { |i| form.invoice_ids.include?(i[:id]) } if form.invoice_ids.any?
          allocate(amount, invoices).first
        end

      payment = Quickbooks::Model::Payment.new
      payment.customer_id = customer.id
      payment.txn_date = form.txn_date_value
      payment.payment_method_ref = Quickbooks::Model::BaseReference.new(form.payment_method_id)
      payment.payment_ref_number = form.reference if form.reference.present?
      payment.private_note = form.memo if form.memo.present?
      payment.total = amount
      payment.line_items = applied.map do |invoice, take|
        line = Quickbooks::Model::Line.new
        line.amount = take
        line.invoice_id = invoice[:id]
        line
      end

      saved = with_service('Payment') { |service| service.create(payment) }
      raise Error, I18n.t(:error_payment_not_saved) unless saved

      # Invoice balances changed: update the local invoices
      applied.each { |invoice, _| sync_invoice(invoice[:id]) }
      saved
    end

    # Every payment the customer has made, newest first (by date, then QuickBooks id), read from QuickBooks
    def customer_payments(customer)
      payments = with_service('Payment') do |service|
        service.all("SELECT * FROM Payment WHERE CustomerRef = '#{customer.id.to_i}' ORDERBY TxnDate DESC")
      end
      Array(payments).sort_by { |p| [p.txn_date || Date.new(1900), p.id.to_i] }.reverse
    end

    # Totals for the customer's payment list: amount received and what's still unapplied (credit)
    def payment_totals(payments)
      sum = ->(values) { values.sum(BigDecimal('0')) { |v| BigDecimal(v.to_s.presence || '0') } }
      { received: sum.call(payments.map(&:total)), unapplied: sum.call(payments.map(&:unapplied_amount)) }
    end

    def load(id)
      payment = with_service('Payment') { |service| service.fetch_by_id(id) }
      raise Error, I18n.t(:notice_payment_not_found) unless payment
      payment
    end

    # The payment as QuickBooks prints it (its payment receipt)
    def pdf(id)
      with_service('Payment') { |service| service.pdf(Struct.new(:id).new(id)) }
    end

    # The invoices a payment was applied to: [[invoice_id, number, amount], ...]
    def applied_invoices(payment)
      Array(payment.line_items).flat_map do |line|
        Array(line.linked_transactions).select { |t| t.txn_type.to_s == 'Invoice' }.map do |t|
          [t.txn_id.to_s, InvoiceWriter.invoice_number(t.txn_id), line.amount]
        end
      end
    end

    def payment_method_name(payment)
      ref = payment.payment_method_ref
      return '' unless ref
      ref.name.presence || payment_methods.detect { |_, id| id == ref.value.to_s }&.first || ref.value.to_s
    end

    def with_service(entity, &block)
      QboConnectionService.with_qbo_service(entity: entity, &block)
    end

    def sync_invoice(id)
      InvoiceSyncService.new.sync_by_id(id)
    rescue StandardError => e
      Rails.logger.warn "[RedmineQboBilling] Could not sync invoice #{id} after a payment: #{e.message}"
    end
  end
end
