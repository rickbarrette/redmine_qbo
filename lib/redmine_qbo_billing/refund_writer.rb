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
  # Customer refunds for canceled orders and returned parts (SOP-OPS-014), the way the SOP does them in QuickBooks:
  #
  #   1. A restocking fee invoice for 30% of the parts (labor carries no fee), its line showing the math, paid
  #      from the customer's credit (their deposit), oldest first.
  #   2. The rest of the customer's credit is refunded: a company check, or a partial refund on the card terminal.
  #   3. The refund is recorded in QuickBooks with the category Accounts Receivable, from the bank account in the
  #      settings, described "Refund for deposit on E1234": a Check for a check, an Expense for a card refund.
  #   4. The credit left on the customer's payments is applied to that check or expense, so the deposit, the fee
  #      invoice and the refund reconcile and the customer's balance comes back to $0.00.
  #
  # Then, as asked on the page: the canceled order's estimate is marked Rejected in QuickBooks, its work orders are
  # set to the canceled status with the reason as a note, and the customer is emailed a summary.
  #
  # Each refund is recorded (QboRefund). Steps 1 to 4 stop at the first failure, and the record says which step
  # failed and what was already done, so it can be finished in QuickBooks. The later steps only add warnings.
  module RefundWriter
    class Error < StandardError; end

    Credit = Struct.new(:payment_id, :date, :reference, :memo, :amount, keyword_init: true)
    Preview = Struct.new(:credits, :credit_total, :parts_amount, :fee_rate, :fee, :refund, keyword_init: true)

    CLOSED_ESTIMATE_STATUSES = %w[Closed Converted Rejected].freeze
    CANCELED_STATUS_NAMES = %w[Canceled Cancelled].freeze

    module_function

    def settings
      Setting.plugin_redmine_qbo || {}
    rescue StandardError
      {}
    end

    # The restocking fee rate in percent (plugin setting, SOP-OPS-014: 30)
    def fee_rate
      rate = BigDecimal(settings['restocking_fee_rate'].to_s.strip, exception: false)
      rate.nil? || rate.negative? ? BigDecimal('30') : rate
    end

    # The product/service on the restocking fee invoice (plugin setting)
    def fee_item
      Item.find_by(id: settings['restocking_item_id']) if settings['restocking_item_id'].present?
    end

    def fee(parts, rate = fee_rate)
      (parts.to_d * rate.to_d / 100).round(2, BigDecimal::ROUND_HALF_UP)
    end

    # The parts on an estimate: its lines that aren't labor (with the lines inside bundles), before tax
    def parts_amount(estimate)
      labor_ids = LaborItems.ids
      parts_lines(Array(estimate&.line_items), labor_ids).sum(BigDecimal('0')) { |line| BigDecimal(line.amount.to_s.presence || '0') }
    end

    def parts_lines(lines, labor_ids)
      lines.flat_map do |line|
        if line.respond_to?(:group_line_detail) && line.group_line_detail
          parts_lines(Array(line.group_line_detail.line_items), labor_ids)
        elsif (ref = sales_detail(line)&.item_ref) && ref.value.present?
          LaborItems.match?(ref, ids: labor_ids) ? [] : [line]
        else
          []
        end
      end
    end

    # A sales line's detail: estimates and invoices name it SalesLineItemDetail (InvoiceLineItem), other
    # transactions SalesItemLineDetail (Line)
    def sales_detail(line)
      if line.respond_to?(:sales_line_item_detail) then line.sales_line_item_detail
      elsif line.respond_to?(:sales_item_line_detail) then line.sales_item_line_detail
      end
    end

    # The customer's credit: their payments' unapplied money, oldest first
    def credits(customer, gateway: RefundGateway.new)
      gateway.unapplied_payments(customer.id).map do |payment|
        Credit.new(payment_id: payment.id.to_s, date: payment.txn_date, reference: payment.payment_ref_number.to_s,
                   memo: payment.private_note.to_s, amount: BigDecimal(payment.unapplied_amount.to_s))
      end
    end

    # The customer's estimates to pick the canceled order from, newest first: [[label, id], ...]
    def estimate_choices(customer)
      Estimate.where(customer_id: customer.id).order(txn_date: :desc, id: :desc).limit(50).map do |estimate|
        total = estimate.respond_to?(:total_amount) && estimate.total_amount ? " · $#{format('%.2f', estimate.total_amount)}" : ''
        ["E#{estimate.doc_number} · #{estimate.txn_date}#{total}", estimate.id.to_s]
      end
    end

    # What the page shows before the refund is made: the credit, the fee and what will be refunded
    def preview(customer, parts:, gateway: RefundGateway.new)
      list = credits(customer, gateway: gateway)
      total = list.sum(BigDecimal('0'), &:amount)
      rate = fee_rate
      amount = fee(parts, rate)
      Preview.new(credits: list, credit_total: total, parts_amount: parts.to_d, fee_rate: rate, fee: amount,
                  refund: [total - amount, BigDecimal('0')].max)
    end

    # "Restocking fee: 30% × $1,026.63 parts on E1068 = $308.00" (on: what the parts are on instead, e.g. "Invoice #1234")
    def fee_description(parts, rate, amount, estimate_number, on: nil)
      on = on.present? ? " on #{on}" : (estimate_number.present? ? " on E#{estimate_number}" : '')
      I18n.t(:text_refund_fee_line, rate: plain(rate), parts: money(parts), on: on, fee: money(amount))
    end

    # "Refund for deposit on E1068" (SOP-OPS-014 step 3)
    def refund_description(estimate_number, card:)
      text = estimate_number.present? ? I18n.t(:text_refund_line, number: estimate_number) : I18n.t(:text_refund_line_credit)
      card ? "#{text} #{I18n.t(:text_refund_line_card)}" : text
    end

    # Makes the refund; returns the QboRefund (done, or incomplete with the step that failed in its message).
    # Raises Error, before anything is made in QuickBooks, when the refund can't be made as asked.
    def refund!(form, user: User.current, gateway: RefundGateway.new, mailer: QboRefundMailer)
      customer = Customer.find_by(id: form.customer_id)
      raise Error, I18n.t(:error_estimate_needs_customer) unless customer

      estimate = load_estimate(form, customer, gateway)
      rate = fee_rate
      parts = form.parts_value
      fee_amount = fee(parts, rate)
      item = fee_item
      raise Error, I18n.t(:error_refund_no_fee_item) if fee_amount.positive? && item.nil?

      payments = gateway.unapplied_payments(customer.id)
      credit = payments.sum(BigDecimal('0')) { |p| BigDecimal(p.unapplied_amount.to_s) }
      raise Error, I18n.t(:error_refund_no_credit) unless credit.positive?
      raise Error, I18n.t(:error_refund_fee_over_credit, fee: money(fee_amount), credit: money(credit)) if fee_amount >= credit

      ar_account = gateway.account_id('Accounts Receivable')
      raise Error, I18n.t(:error_refund_no_ar_account) unless ar_account
      bank_account = settings[form.check? ? 'refund_check_account_id' : 'refund_card_account_id'].presence || gateway.account_id('Bank')
      raise Error, I18n.t(:error_refund_no_bank_account) unless bank_account

      record = QboRefund.create!(customer_id: customer.id, estimate_id: estimate&.id, estimate_number: estimate&.doc_number,
                                 user: user, txn_date: form.txn_date_value, method: form.method,
                                 check_number: form.check? ? form.check_number : nil, reason: form.reason,
                                 parts_amount: parts, fee_rate: rate, fee_amount: fee_amount, credit_amount: credit,
                                 status: 'incomplete')
      warnings = []

      if fee_amount.positive?
        fee_paid = step(record, :fee) { charge_fee(record, customer, item, gateway) }
        return record unless fee_paid
      end
      refunded = step(record, :refund) { record_refund(record, customer, form, ar_account, bank_account, gateway) }
      return record unless refunded

      begin
        record.update!(balance_after: gateway.customer_balance(customer.id))
      rescue StandardError
        warnings << I18n.t(:text_refund_balance_unknown)
      end
      warnings << close_estimate(record, estimate, gateway) if form.close_estimate? && estimate
      warnings << cancel_issues(record, estimate, form, user) if form.cancel_issues? && estimate
      warnings << email_customer(record, customer, mailer) if form.email_customer?
      record.update!(status: 'done', message: warnings.compact.join("\n").presence)
      record
    end

    # The canceled order's estimate, which must be the customer's
    def load_estimate(form, customer, gateway)
      return nil if form.estimate_id.blank?

      estimate = gateway.estimate(form.estimate_id)
      raise Error, I18n.t(:notice_estimate_not_found) unless estimate
      raise Error, I18n.t(:error_refund_estimate_customer) unless estimate.customer_ref&.value.to_s == customer.id.to_s

      estimate
    end

    # Runs one of the steps that must all succeed; on failure records which step and why
    def step(record, name)
      yield
      true
    rescue StandardError => e
      detail = e.respond_to?(:detail) && e.detail.present? ? "#{e.message}: #{e.detail}" : e.message
      Rails.logger.error "[RedmineQboBilling] Refund #{record.id}, #{name}: #{detail}"
      record.update!(message: I18n.t(:"error_refund_step_#{name}", error: detail))
      false
    end

    # Step 1: the restocking fee invoice, paid from the customer's credit
    def charge_fee(record, customer, item, gateway)
      invoice = Quickbooks::Model::Invoice.new
      invoice.customer_id = customer.id
      invoice.txn_date = record.txn_date
      invoice.private_note = I18n.t(:text_refund_private_note, reason: record.reason)
      line = Quickbooks::Model::InvoiceLineItem.new
      line.amount = record.fee_amount
      line.description = fee_description(record.parts_amount, record.fee_rate, record.fee_amount, record.estimate_number)
      line.sales_item! do |detail|
        detail.item_id = item.id
        detail.quantity = 1
        detail.unit_price = record.fee_amount
      end
      invoice.line_items = [line]
      saved = gateway.create_invoice(invoice)
      raise Error, I18n.t(:error_refund_fee_not_saved) unless saved&.id

      record.update!(fee_invoice_id: saved.id.to_s, fee_invoice_number: saved.doc_number.to_s)
      # QuickBooks may already have applied the customer's credit to the new invoice ("Automatically apply credits")
      owed = BigDecimal(gateway.invoice(saved.id).balance.to_s.presence || '0')
      gateway.unapplied_payments(customer.id).each do |payment|
        break unless owed.positive?

        take = [owed, BigDecimal(payment.unapplied_amount.to_s)].min
        next unless take.positive?

        gateway.apply_payment(payment, take, saved.id, 'Invoice')
        gateway.sync_payment(payment.id)
        owed -= take
      end
      raise Error, I18n.t(:error_refund_fee_unpaid, amount: money(owed)) if owed.positive?

      gateway.sync_invoice(saved.id)
    end

    # Steps 2 to 4: the refund check or expense for the rest of the credit, and the credit applied to it
    def record_refund(record, customer, form, ar_account, bank_account, gateway)
      payments = gateway.unapplied_payments(customer.id)
      amount = payments.sum(BigDecimal('0')) { |p| BigDecimal(p.unapplied_amount.to_s) }
      raise Error, I18n.t(:error_refund_nothing_left) unless amount.positive?

      card = !form.check?
      purchase = Quickbooks::Model::Purchase.new
      purchase.payment_type = card ? 'Cash' : 'Check'
      purchase.doc_number = record.check_number unless card
      purchase.txn_date = record.txn_date
      purchase.account_ref = Quickbooks::Model::BaseReference.new(bank_account.to_s)
      payee = Quickbooks::Model::BaseReference.new(customer.id.to_s)
      payee.type = 'Customer'
      purchase.entity_ref = payee
      purchase.private_note = I18n.t(:text_refund_private_note, reason: record.reason)
      line = Quickbooks::Model::PurchaseLineItem.new
      line.amount = amount
      line.description = refund_description(record.estimate_number, card: card)
      line.account_based_expense! do |detail|
        detail.account_ref = Quickbooks::Model::BaseReference.new(ar_account.to_s)
        detail.customer_ref = Quickbooks::Model::BaseReference.new(customer.id.to_s)
      end
      purchase.line_items = [line]
      saved = gateway.create_purchase(purchase)
      raise Error, I18n.t(:error_refund_not_saved) unless saved&.id

      record.update!(purchase_id: saved.id.to_s, refund_amount: amount)
      # The credit is applied to the check ("Check") or the expense ("Expense")
      payments.each do |payment|
        gateway.apply_payment(payment, BigDecimal(payment.unapplied_amount.to_s), saved.id, card ? 'Expense' : 'Check')
        gateway.sync_payment(payment.id)
      end
    end

    # Marks the canceled order's estimate Rejected; returns a warning, or nil
    def close_estimate(record, estimate, gateway)
      return nil if CLOSED_ESTIMATE_STATUSES.include?(estimate.txn_status.to_s)

      gateway.reject_estimate(estimate)
      gateway.sync_estimate(estimate.id)
      record.update!(estimate_closed: true)
      nil
    rescue StandardError => e
      I18n.t(:text_refund_estimate_not_closed, error: e.message)
    end

    # Sets the estimate's open work orders to the canceled status, with the reason as a note (Work Orders §5)
    def cancel_issues(record, estimate, form, user)
      status = canceled_status
      return I18n.t(:text_refund_no_canceled_status) unless status

      ids = Issue.where(estimate_id: estimate.id).pluck(:id) + QboEstimateLineIssue.where(estimate_id: estimate.id).pluck(:issue_id)
      note = I18n.t(:text_refund_issue_note, reason: form.reason, fee: money(record.fee_amount),
                                             refund: money(record.refund_amount), method: record.method_name)
      failed = []
      canceled = Issue.where(id: ids.uniq).includes(:status).reject(&:closed?).filter_map do |issue|
        issue.init_journal(user, note)
        issue.status = status
        if issue.save
          issue.id
        else
          failed << "##{issue.id} (#{issue.errors.full_messages.join(', ')})"
          nil
        end
      end
      record.update!(canceled_issue_ids: canceled)
      failed.any? ? I18n.t(:text_refund_issues_not_canceled, issues: failed.join('; ')) : nil
    end

    # The work order status for canceled orders (plugin setting, else a closed status named Canceled)
    def canceled_status
      id = settings['refund_canceled_status_id']
      (IssueStatus.find_by(id: id) if id.present?) ||
        IssueStatus.where(is_closed: true).detect { |s| CANCELED_STATUS_NAMES.include?(s.name.to_s.strip) }
    end

    # Emails the customer a summary; returns a warning, or nil
    def email_customer(record, customer, mailer)
      email = customer.email.to_s.strip
      return I18n.t(:text_refund_no_email) if email.blank?

      mailer.refund_summary(record, email).deliver_now
      record.update!(emailed_to: email)
      nil
    rescue StandardError => e
      I18n.t(:text_refund_email_failed, error: e.message)
    end

    def money(amount)
      whole, cents = format('%.2f', amount.to_d.abs).split('.')
      "#{'-' if amount.to_d.negative?}$#{whole.reverse.scan(/\d{1,3}/).join(',').reverse}.#{cents}"
    end

    def plain(number)
      number = number.to_d
      number == number.to_i ? number.to_i.to_s : number.to_s('F')
    end
  end
end
