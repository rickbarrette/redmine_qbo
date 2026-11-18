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
  # Refunds of completed work: an invoice that's billed and paid in full (SOP-OPS-014 for the restocking fee).
  # QuickBooks' way to refund a paid sale is a Refund Receipt, which this makes:
  #
  #   * the invoice lines refunded (all or part of each), with their product/service and tax code, so the income
  #     and the sales tax come back off the books the way they went on (QuickBooks works out the tax);
  #   * the invoice's discount, if it had one, in proportion to what's refunded;
  #   * the restocking fee, when it's charged, as a negative line with the restocking fee product/service:
  #     its rate (plugin setting) of the parts refunded. Labor carries no fee, and work with no parts has none;
  #   * paid out of the refund check or card refund bank account in the settings, by company check (its number)
  #     or a refund on the card terminal.
  #
  # The invoice itself stays as it is, paid. Each refund is recorded (QboRefund, kind invoice) with the lines it
  # refunded, so a line can't be refunded for more than it was billed across several refunds. Then, as asked on
  # the page, the refund is noted on the invoice's work orders and the customer is emailed a summary.
  module InvoiceRefundWriter
    Error = RefundWriter::Error

    # An invoice line that can be refunded, with what earlier refunds already took of it
    Line = Struct.new(:key, :item_id, :item_name, :description, :quantity, :rate, :amount, :taxable, :parts,
                      :refunded_quantity, :refunded_amount, keyword_init: true) do
      def remaining_amount
        [amount - refunded_amount, BigDecimal('0')].max
      end

      def remaining_quantity
        quantity && [quantity - refunded_quantity, BigDecimal('0')].max
      end

      def refundable?
        remaining_amount.positive?
      end

      def label
        [item_name.presence, description.presence].compact.uniq.join(' · ')
      end
    end

    # A line being refunded: the invoice line, the quantity (nil when only an amount is refunded) and the amount
    Refunding = Struct.new(:line, :quantity, :amount, keyword_init: true)

    # What a refund comes to: the lines, the invoice discount's share, the fee, the tax (estimated before
    # QuickBooks works it out) and the refund
    Plan = Struct.new(:refunding, :lines_amount, :parts_amount, :discount_rate, :discount, :fee_rate, :fee,
                      :tax_rate, :tax, :refund, keyword_init: true)

    module_function

    def settings
      RefundWriter.settings
    end

    # Billed and paid in full: a total, and nothing left owing
    def paid_in_full?(remote)
      total = BigDecimal(remote&.total.to_s.presence || '0')
      balance = BigDecimal(remote&.balance.to_s.presence || '0')
      total.positive? && balance <= 0
    end

    # The customer's paid invoices to pick from on the Refund page, newest first: [[label, id], ...]
    def invoice_choices(customer)
      Invoice.where(customer_id: customer.id).where('balance <= 0 AND total_amount > 0')
             .order(txn_date: :desc, id: :desc).limit(50).map do |invoice|
        ["##{invoice.doc_number} · #{invoice.txn_date} · #{RefundWriter.money(invoice.total_amount)}", invoice.id.to_s]
      end
    end

    # The invoice's lines that can be refunded (bundles opened up into their lines), with what this invoice's
    # earlier refunds took of each
    def lines(remote, refunds: QboRefund.of_invoice(remote.id))
      taken = Hash.new { |hash, key| hash[key] = [BigDecimal('0'), BigDecimal('0')] }
      refunds.each do |refund|
        refund.refunded_lines.each do |line|
          taken[line.key][0] += BigDecimal(line.quantity.to_s.presence || '0')
          taken[line.key][1] += line.amount.to_d
        end
      end

      labor_ids = LaborItems.ids
      sales_lines(Array(remote.line_items)).filter_map do |line, key|
        detail = RefundWriter.sales_detail(line)
        amount = BigDecimal(line.amount.to_s.presence || '0')
        next unless amount.positive?

        ref = detail&.item_ref
        quantity = detail&.quantity.nil? ? nil : BigDecimal(detail.quantity.to_s)
        quantity = nil unless quantity&.positive?
        Line.new(key: key, item_id: ref&.value.to_s.presence, item_name: ref&.name.to_s, description: line.description.to_s,
                 quantity: quantity, rate: detail&.unit_price.nil? ? nil : BigDecimal(detail.unit_price.to_s),
                 amount: amount, taxable: detail&.tax_code_ref&.value.to_s == 'TAX',
                 parts: ref.present? && ref.value.present? && !LaborItems.match?(ref, ids: labor_ids),
                 refunded_quantity: taken[key][0], refunded_amount: taken[key][1])
      end
    end

    # The sales lines with a key for each: its QuickBooks line id, or for a line in a bundle the bundle's id and
    # its place in it
    def sales_lines(lines, prefix = nil)
      lines.each_with_index.flat_map do |line, index|
        key = "#{prefix}#{line.id.presence || index + 1}"
        if line.respond_to?(:group_line_detail) && line.group_line_detail
          sales_lines(Array(line.group_line_detail.line_items), "#{key}.")
        elsif RefundWriter.sales_detail(line)
          [[line, key]]
        else
          []
        end
      end
    end

    # The invoice's discount, as a share of its lines (0.1 for 10% off)
    def discount_rate(remote)
      discount = EstimateWriter.discount_total(remote).to_d
      subtotal = sales_lines(Array(remote.line_items)).sum(BigDecimal('0')) { |line, _| BigDecimal(line.amount.to_s.presence || '0') }
      return BigDecimal('0') unless discount.positive? && subtotal.positive?

      [discount / subtotal, BigDecimal('1')].min
    end

    # The invoice's sales tax, as a share of its taxable lines after the discount, to estimate the tax refunded
    def tax_rate(remote, invoice_lines = lines(remote, refunds: []))
      tax = BigDecimal(remote.txn_tax_detail&.total_tax.to_s.presence || '0')
      taxable = invoice_lines.select(&:taxable).sum(BigDecimal('0'), &:amount) * (1 - discount_rate(remote))
      tax.positive? && taxable.positive? ? tax / taxable : BigDecimal('0')
    end

    # Works out the refund from the form's lines: [plan, errors]
    def plan(remote, form, invoice_lines: lines(remote))
      errors = []
      by_key = invoice_lines.index_by(&:key)
      refunding = form.chosen.filter_map do |key, choice|
        line = by_key[key]
        if line.nil?
          errors << I18n.t(:error_refund_line_gone)
          next
        end

        refunding_line(line, choice, errors)
      end

      lines_amount = refunding.sum(BigDecimal('0'), &:amount)
      parts = refunding.select { |r| r.line.parts }.sum(BigDecimal('0'), &:amount)
      rate = discount_rate(remote)
      discount = (lines_amount * rate).round(2, BigDecimal::ROUND_HALF_UP)
      fee_rate = RefundWriter.fee_rate
      fee = form.charge_fee? ? RefundWriter.fee(parts, fee_rate) : BigDecimal('0')
      tax_rate = tax_rate(remote, invoice_lines)
      taxable = refunding.select { |r| r.line.taxable }.sum(BigDecimal('0'), &:amount) * (1 - rate)
      tax = (taxable * tax_rate).round(2, BigDecimal::ROUND_HALF_UP)
      refund = lines_amount - discount + tax - fee
      if refunding.any? && fee >= lines_amount - discount
        errors << I18n.t(:error_refund_fee_over_lines, fee: RefundWriter.money(fee), amount: RefundWriter.money(lines_amount - discount))
      end

      plan = Plan.new(refunding: refunding, lines_amount: lines_amount, parts_amount: parts, discount_rate: rate,
                      discount: discount, fee_rate: fee_rate, fee: fee, tax_rate: tax_rate, tax: tax,
                      refund: [refund, BigDecimal('0')].max)
      [plan, errors.uniq]
    end

    # A line being refunded, from what was posted for it: the quantity and the amount (by default the quantity
    # at the line's rate, or what's left of the line). Adds to errors when it can't be refunded.
    def refunding_line(line, choice, errors)
      name = line.label.presence || line.key
      quantity = choice.quantity_value
      quantity = nil if line.quantity.nil? || line.rate.nil?
      amount = choice.amount_value
      amount ||= quantity ? (quantity * line.rate).round(2) : line.remaining_amount

      if quantity && (quantity <= 0 || quantity > line.remaining_quantity)
        errors << I18n.t(:error_refund_line_quantity, line: name, quantity: RefundWriter.plain(line.remaining_quantity))
        return nil
      end
      if amount.nil? || amount <= 0
        errors << I18n.t(:error_refund_line_amount, line: name)
        return nil
      end
      if amount > line.remaining_amount
        errors << I18n.t(:error_refund_line_over, line: name, amount: RefundWriter.money(line.remaining_amount))
        return nil
      end

      # A partial amount (not the quantity at the line's rate) is refunded as an amount alone, so it doesn't
      # use up the line's quantity
      quantity = nil if quantity && (quantity * line.rate).round(2) != amount
      Refunding.new(line: line, quantity: quantity, amount: amount)
    end

    # The quantity to offer for a line: what's left of it, when that's what's left of its amount at its rate
    def default_quantity(line)
      quantity = line.remaining_quantity
      return nil unless quantity&.positive? && line.rate

      (quantity * line.rate).round(2) == line.remaining_amount ? quantity : nil
    end

    # Makes the refund receipt; returns the QboRefund (done, or incomplete with why in its message). Raises
    # Error, before anything is made in QuickBooks, when the refund can't be made as asked.
    def refund!(form, user: User.current, gateway: RefundGateway.new, mailer: QboRefundMailer)
      customer = Customer.find_by(id: form.customer_id)
      raise Error, I18n.t(:error_estimate_needs_customer) unless customer

      remote = gateway.invoice(form.invoice_id)
      raise Error, I18n.t(:notice_invoice_not_found) unless remote
      raise Error, I18n.t(:error_refund_invoice_customer) unless remote.customer_ref&.value.to_s == customer.id.to_s
      raise Error, I18n.t(:error_refund_invoice_not_paid) unless paid_in_full?(remote)

      plan, errors = plan(remote, form)
      raise Error, errors.join(' ') if errors.any?
      raise Error, I18n.t(:error_refund_no_lines) if plan.refunding.empty?

      item = RefundWriter.fee_item
      raise Error, I18n.t(:error_refund_no_fee_item) if plan.fee.positive? && item.nil?

      bank_account = settings[form.check? ? 'refund_check_account_id' : 'refund_card_account_id'].presence || gateway.account_id('Bank')
      raise Error, I18n.t(:error_refund_no_bank_account) unless bank_account

      paid = BigDecimal(remote.total.to_s) - BigDecimal(remote.balance.to_s.presence || '0')
      record = QboRefund.create!(kind: 'invoice', customer_id: customer.id, invoice_id: remote.id,
                                 invoice_number: remote.doc_number.to_s, user: user, txn_date: form.txn_date_value,
                                 method: form.method, check_number: form.check? ? form.check_number : nil,
                                 reason: form.reason, lines_amount: plan.lines_amount, discount_amount: plan.discount,
                                 parts_amount: plan.parts_amount, fee_rate: plan.fee_rate, fee_amount: plan.fee,
                                 tax_amount: plan.tax, credit_amount: paid, refund_amount: plan.refund,
                                 refunded_lines: refunded_lines(plan), status: 'incomplete')

      made = RefundWriter.step(record, :receipt) do
        receipt = build_receipt(record, remote, plan, form, item, bank_account, gateway)
        saved = gateway.create_refund_receipt(receipt)
        raise Error, I18n.t(:error_refund_not_saved) unless saved&.id

        tax = saved.txn_tax_detail&.total_tax
        record.update!(purchase_id: saved.id.to_s, receipt_number: saved.doc_number.to_s,
                       refund_amount: saved.total.nil? ? plan.refund : BigDecimal(saved.total.to_s),
                       tax_amount: tax.nil? ? plan.tax : BigDecimal(tax.to_s))
      end
      return record unless made

      warnings = []
      warnings << note_issues(record, user) if form.note_issues?
      warnings << RefundWriter.email_customer(record, customer, mailer) if form.email_customer?
      record.update!(status: 'done', message: warnings.compact.join("\n").presence)
      record
    end

    def refunded_lines(plan)
      plan.refunding.map do |r|
        QboRefund::RefundedLine.new(key: r.line.key, description: r.line.label, quantity: r.quantity,
                                    amount: r.amount, parts: r.line.parts)
      end
    end

    # The QuickBooks Refund Receipt: the lines refunded, the discount's share, the restocking fee
    def build_receipt(record, remote, plan, form, fee_item, bank_account, gateway)
      receipt = Quickbooks::Model::RefundReceipt.new
      receipt.customer_ref = Quickbooks::Model::BaseReference.new(record.customer_id.to_s)
      receipt.txn_date = record.txn_date
      receipt.deposit_to_account_ref = Quickbooks::Model::BaseReference.new(bank_account.to_s)
      method_id = gateway.payment_method_id(form.check? ? :check : :card)
      receipt.payment_method_ref = Quickbooks::Model::BaseReference.new(method_id) if method_id
      receipt.payment_ref_number = record.check_number if form.check?
      receipt.bill_email = remote.bill_email if remote.bill_email&.address.present?
      receipt.customer_memo = I18n.t(:text_refund_receipt_memo, number: record.invoice_number)
      receipt.private_note = I18n.t(:text_refund_invoice_private_note, number: record.invoice_number, reason: record.reason)
      receipt.apply_tax_after_discount = true if plan.discount.positive?

      lines = plan.refunding.map { |r| receipt_line(r) }
      lines << discount_line(plan) if plan.discount.positive?
      lines << fee_line(record, fee_item) if plan.fee.positive?
      lines.each_with_index { |line, index| line.line_num = index + 1 }
      receipt.line_items = lines
      receipt
    end

    # A refunded line: the invoice line's product/service and tax code. Its quantity and rate go with it when
    # the amount is that quantity at the line's rate (refunding_line); a partial amount goes as an amount alone.
    def receipt_line(refunding)
      line = refunding.line
      remote = Quickbooks::Model::Line.new
      remote.description = line.description
      remote.amount = refunding.amount
      remote.sales_item! do |detail|
        detail.item_ref = Quickbooks::Model::BaseReference.new(line.item_id) if line.item_id
        if refunding.quantity
          detail.quantity = refunding.quantity
          detail.unit_price = line.rate
        end
        detail.tax_code_ref = Quickbooks::Model::BaseReference.new(line.taxable ? 'TAX' : 'NON')
      end
      remote
    end

    def discount_line(plan)
      remote = Quickbooks::Model::Line.new
      remote.amount = plan.discount
      remote.discount! { |detail| detail.percent_based = false }
      remote
    end

    # The restocking fee, kept back: a negative line, so the fee is income and the refund is less by it
    def fee_line(record, item)
      remote = Quickbooks::Model::Line.new
      remote.amount = -record.fee_amount
      remote.description = RefundWriter.fee_description(record.parts_amount, record.fee_rate, record.fee_amount,
                                                        nil, on: record.document_label)
      remote.sales_item! do |detail|
        detail.item_id = item.id
        detail.quantity = 1
        detail.unit_price = -record.fee_amount
        detail.tax_code_ref = Quickbooks::Model::BaseReference.new('NON')
      end
      remote
    end

    # Notes the refund on the invoice's work orders (their status is left alone); returns a warning, or nil
    def note_issues(record, user)
      issues = Invoice.find_by(id: record.invoice_id)&.issues.to_a
      return nil if issues.empty?

      note = I18n.t(:text_refund_invoice_issue_note, amount: RefundWriter.money(record.refund_amount),
                                                     number: record.invoice_number, method: record.method_name,
                                                     reason: record.reason)
      failed = []
      noted = issues.filter_map do |issue|
        issue.init_journal(user, note)
        if issue.save
          issue.id
        else
          failed << "##{issue.id} (#{issue.errors.full_messages.join(', ')})"
          nil
        end
      end
      record.update!(noted_issue_ids: noted)
      failed.any? ? I18n.t(:text_refund_issues_not_noted, issues: failed.join('; ')) : nil
    end
  end
end
