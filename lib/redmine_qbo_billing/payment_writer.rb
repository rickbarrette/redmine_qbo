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
  #
  # A saved payment can be edited the same way (date, method, reference, memo, amount and the invoices it
  # pays); its customer stays. Left as it was, it keeps the amounts it already applied to each invoice.
  module PaymentWriter
    Error = EstimateWriter::Error
    Conflict = EstimateWriter::Conflict
    INVOICE = 'Invoice'.freeze

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

    # The customer's invoices with a balance, oldest first (by date, then number). For a payment being edited
    # (payment:, the QuickBooks payment), what it paid on each invoice counts as still open, so the invoices it
    # pays are listed even when it paid them off.
    def open_invoices(customer, payment: nil)
      invoices = with_service('Invoice') do |service|
        service.query("SELECT * FROM Invoice WHERE CustomerRef = '#{customer.id.to_i}' ORDERBY TxnDate", per_page: 1000).entries
      end
      paid_here = payment ? applied_amounts(payment) : {}

      Array(invoices).map { |i| [i, BigDecimal(i.balance.to_s.presence || '0') + paid_here.fetch(i.id.to_s, 0)] }
                     .select { |_, balance| balance > 0 }
                     .sort_by { |i, _| [i.txn_date || Date.new(1900), i.doc_number.to_s.rjust(12, '0')] }
                     .map do |i, balance|
        { id: i.id.to_s, doc_number: i.doc_number.to_s, date: i.txn_date.to_s, due_date: i.due_date.to_s,
          total: i.total.to_s, balance: balance.to_s('F') }
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

    # Creates the payment in QuickBooks (or updates the one being edited) and returns it. Open invoices are
    # read again here, so the payment goes on what's open right now.
    def save(form)
      return update(form) if form.persisted?

      customer = Customer.find_by(id: form.customer_id)
      raise Error, I18n.t(:error_estimate_needs_customer) unless customer

      amount = form.amount_value.round(2)
      applied = allocation(form, customer, amount)

      payment = Quickbooks::Model::Payment.new
      payment.customer_id = customer.id
      fill(payment, form, amount, applied)
      payment.payment_ref_number = nil if form.reference.blank?
      payment.private_note = nil if form.memo.blank?

      saved = with_service('Payment') { |service| service.create(payment) }
      raise Error, I18n.t(:error_payment_not_saved) unless saved

      # Invoice balances changed: update the local invoices, and cache the payment for reports
      applied.each { |invoice_id, _| sync_invoice(invoice_id) }
      sync_payment(saved.id)
      saved
    end

    # A saved payment on the Edit payment page
    def load_form(id)
      payment = load(id)
      applied = applied_amounts(payment)
      PaymentForm.new(
        id: payment.id.to_s,
        sync_token: payment.sync_token.to_s,
        customer_id: payment.customer_ref&.value.to_s,
        customer_name: payment.customer_ref&.name.presence || Customer.find_by(id: payment.customer_ref&.value)&.name,
        txn_date: payment.txn_date&.iso8601,
        payment_method_id: payment.payment_method_ref&.value.to_s,
        reference: payment.payment_ref_number.to_s,
        amount: BigDecimal(payment.total.to_s).round(2).to_s('F'),
        deposit: applied.empty? ? '1' : '0',
        memo: payment.private_note.to_s,
        invoice_ids: applied.keys,
        locked: edit_blocked(payment)
      )
    end

    # Saves the changes to a payment. Its customer stays. If the amount and the ticked invoices are the
    # same as before, each invoice keeps the amount it had; otherwise the amount is spread again, oldest first.
    def update(form)
      applied = nil
      previously = []
      saved = with_service('Payment') do |service|
        remote = service.fetch_by_id(form.id)
        raise Error, I18n.t(:notice_payment_not_found) unless remote
        raise Conflict, I18n.t(:error_payment_changed_in_quickbooks) if remote.sync_token.to_s != form.sync_token.to_s
        blocked = edit_blocked(remote)
        raise Error, blocked if blocked

        customer = Customer.find_by(id: remote.customer_ref&.value)
        raise Error, I18n.t(:error_estimate_needs_customer) unless customer

        amount = form.amount_value.round(2)
        before = applied_amounts(remote)
        applied =
          if !form.deposit? && before.any? && amount == BigDecimal(remote.total.to_s) && form.invoice_ids.sort == before.keys.sort
            before.to_a
          else
            allocation(form, customer, amount, payment: remote)
          end
        previously = before.keys

        payment = Quickbooks::Model::Payment.new
        payment.id = remote.id
        payment.sync_token = remote.sync_token
        payment.customer_ref = remote.customer_ref
        fill(payment, form, amount, applied)
        service.update(payment, sparse: true)
      end
      raise Error, I18n.t(:error_payment_not_saved) unless saved

      # Balances changed on the invoices it paid before and the ones it pays now
      (previously + applied.map(&:first)).uniq.each { |invoice_id| sync_invoice(invoice_id) }
      sync_payment(saved.id)
      saved
    end

    # Where the payment goes: [[invoice_id, amount], ...] (nothing for a deposit)
    def allocation(form, customer, amount, payment: nil)
      return [] if form.deposit?

      invoices = open_invoices(customer, payment: payment)
      invoices = invoices.select { |i| form.invoice_ids.include?(i[:id]) } if form.invoice_ids.any?
      allocate(amount, invoices).first.map { |invoice, take| [invoice[:id], take] }
    end

    # The form's details on a QuickBooks payment, applied as given ([[invoice_id, amount], ...])
    def fill(payment, form, amount, applied)
      payment.txn_date = form.txn_date_value
      payment.payment_method_ref = Quickbooks::Model::BaseReference.new(form.payment_method_id)
      payment.payment_ref_number = form.reference.to_s
      payment.private_note = form.memo.to_s
      payment.total = amount
      payment.line_items = applied.map do |invoice_id, take|
        line = Quickbooks::Model::Line.new
        line.amount = take
        line.invoice_id = invoice_id
        line
      end
      payment
    end

    # Why a payment can't be edited here, or nil: it also applies credit memos or other transactions, which
    # this page doesn't show (saving would drop them)
    def edit_blocked(payment)
      others = Array(payment.line_items).flat_map { |line| Array(line.linked_transactions) }
                                        .reject { |t| t.txn_type.to_s == INVOICE }
      others.any? ? I18n.t(:error_payment_not_editable, types: others.map { |t| t.txn_type.to_s }.uniq.join(', ')) : nil
    end

    # What the payment pays on each invoice: { invoice_id => amount }
    def applied_amounts(payment)
      applied_invoices(payment).each_with_object(Hash.new(BigDecimal('0'))) do |(invoice_id, _, amount), sums|
        sums[invoice_id] += BigDecimal(amount.to_s.presence || '0')
      end.to_h
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

    def sync_payment(id)
      PaymentSyncService.new.sync_by_id(id)
    rescue StandardError => e
      Rails.logger.warn "[RedmineQboBilling] Could not cache payment #{id}: #{e.message}"
    end

    def sync_invoice(id)
      InvoiceSyncService.new.sync_by_id(id)
    rescue StandardError => e
      Rails.logger.warn "[RedmineQboBilling] Could not sync invoice #{id} after a payment: #{e.message}"
    end
  end
end
