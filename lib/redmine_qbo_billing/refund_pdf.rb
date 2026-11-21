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
  # A refund as a PDF (SOP-OPS-014): what was refunded and how, from what Redmine recorded when it was made, so it
  # can be printed or filed without opening QuickBooks (QuickBooks has no PDF of a check or an expense).
  class RefundPdf
    include Redmine::I18n

    WIDTH = 190

    def initialize(refund)
      @refund = refund
    end

    def render
      pdf = ::Redmine::Export::PDF::ITCPDF.new(current_language)
      pdf.set_title(title)
      pdf.alias_nb_pages
      pdf.footer_date = format_date(User.current.today)
      pdf.add_page

      pdf.SetFontStyle('B', 14)
      pdf.RDMMultiCell(WIDTH, 7, shop_name)
      pdf.SetFontStyle('B', 12)
      pdf.RDMMultiCell(WIDTH, 7, title)
      pdf.ln(3)

      details(pdf)
      pdf.ln(4)
      amounts(pdf)
      pdf.ln(4)
      notes(pdf)
      signature(pdf) if @refund.check?
      pdf.output
    end

    def title
      "#{l(:label_refund)} · #{@refund.customer&.name} · #{format_date(@refund.txn_date)}"
    end

    def filename
      "refund-#{@refund.txn_date}-#{@refund.customer&.name.to_s.parameterize.presence || @refund.customer_id}.pdf"
    end

    private

    def details(pdf)
      rows = [[l(:label_customer), @refund.customer&.name.to_s],
              [l(:label_refund_date), format_date(@refund.txn_date)],
              @refund.invoice? ? [l(:label_refund_invoice), @refund.document_label] :
                [l(:label_refund_estimate), @refund.estimate_number.present? ? "E#{@refund.estimate_number}" : l(:label_refund_no_estimate)],
              [l(:label_refund_reason), @refund.reason.to_s]]
      rows.each { |label, value| row(pdf, label, value) }
    end

    def amounts(pdf)
      pdf.SetFontStyle('B', 10)
      pdf.RDMCell(WIDTH, 6, l(:label_refund_summary), 'B', 1)
      pdf.SetFontStyle('', 10)
      fee = @refund.fee_amount.to_d
      if @refund.invoice?
        invoice_lines(pdf)
      else
        money_row(pdf, l(:label_refund_credit), @refund.credit_amount)
      end
      if fee.positive?
        label = l(:label_refund_pdf_fee, rate: RefundWriter.plain(@refund.fee_rate), parts: RefundWriter.money(@refund.parts_amount))
        label += " · #{l(:label_refund_fee_invoice, number: @refund.fee_invoice_number)}" if @refund.fee_invoice_number.present?
        money_row(pdf, label, -fee)
      end
      pdf.SetFontStyle('B', 11)
      money_row(pdf, "#{l(:label_refund_amount)} · #{method_text}", @refund.refund_amount, border: 'T')
      pdf.SetFontStyle('', 10)
      unless @refund.balance_after.nil?
        money_row(pdf, l(:label_refund_balance_after), @refund.balance_after)
      end
    end

    # A paid invoice's refund: each line refunded, the discount's share and the sales tax
    def invoice_lines(pdf)
      @refund.refunded_lines.each do |line|
        quantity = line.quantity.present? ? " (#{RefundWriter.plain(BigDecimal(line.quantity.to_s))})" : ''
        money_row(pdf, "#{line.description.truncate(90)}#{quantity}", line.amount)
      end
      money_row(pdf, l(:label_refund_discount), -@refund.discount_amount.to_d) if @refund.discount_amount.to_d.positive?
      money_row(pdf, l(:label_refund_tax), @refund.tax_amount)
    end

    def notes(pdf)
      pdf.SetFontStyle('', 9)
      issues = Issue.where(id: @refund.canceled_issue_ids).to_a
      row(pdf, l(:label_refund_pdf_work_orders), issues.map { |i| "#{i.tracker} ##{i.id}: #{i.subject}" }.join("\n")) if issues.any?
      row(pdf, l(:label_refund_pdf_estimate), l(:text_refund_pdf_estimate_rejected, number: @refund.estimate_number)) if @refund.estimate_closed?
      if @refund.invoice? && @refund.receipt_number.present?
        row(pdf, l(:label_refund_receipt), l(:text_refund_receipt_number, number: @refund.receipt_number))
      end
      row(pdf, l(:label_refund_recorded_by), "#{@refund.user&.name} · #{format_time(@refund.created_at)}")
      row(pdf, l(:label_refund_incomplete), @refund.message.to_s) unless @refund.done?
    end

    # For a refund check: the customer signs for it
    def signature(pdf)
      pdf.ln(14)
      pdf.SetFontStyle('', 10)
      pdf.RDMCell(110, 6, l(:label_refund_received_by), 'T', 0)
      pdf.RDMCell(10, 6, '', 0, 0)
      pdf.RDMCell(70, 6, l(:label_date), 'T', 1)
    end

    def method_text
      @refund.check? ? "#{@refund.method_name} ##{@refund.check_number}" : @refund.method_name
    end

    def row(pdf, label, value)
      pdf.SetFontStyle('B', 10)
      pdf.RDMCell(50, 6, label.to_s, 0, 0)
      pdf.SetFontStyle('', 10)
      pdf.RDMMultiCell(WIDTH - 50, 6, value.to_s)
    end

    def money_row(pdf, label, amount, border: 0)
      pdf.RDMCell(WIDTH - 40, 7, label.to_s, border, 0)
      pdf.RDMCell(40, 7, RefundWriter.money(amount), border, 1, 'R')
    end

    def shop_name
      RedmineQboBilling.mail_settings[:shop_name].presence || Setting.app_title
    rescue StandardError
      Setting.app_title
    end
  end
end
