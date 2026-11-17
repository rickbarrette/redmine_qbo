#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Customer refunds (SOP-OPS-014): the Refund page for a customer with credit, and a refund once it's made
class QboRefundsController < ApplicationController
  before_action :authorize_global

  QBO_ERRORS = QboEstimatesController::QBO_ERRORS

  def new
    @customer = Customer.find_by(id: params[:customer_id])
    return render_404 unless @customer

    @form = RedmineQboBilling::RefundForm.new(customer_id: @customer.id.to_s, estimate_id: params[:estimate_id].to_s,
                                              txn_date: User.current.today.iso8601, method: 'check',
                                              close_estimate: '1', cancel_issues: '1', email_customer: '1')
    @form.parts_amount = estimate_parts(@form.estimate_id)
    load_page
  end

  def create
    @form = RedmineQboBilling::RefundForm.from_params(params.require(:refund).permit(*RedmineQboBilling::RefundForm::ATTRIBUTES))
    @customer = Customer.find_by(id: @form.customer_id)
    return render_404 unless @customer
    return show_form unless @form.valid?

    refund = RedmineQboBilling::RefundWriter.refund!(@form)
    if refund.done?
      flash[:notice] = l(:notice_refund_done, amount: RedmineQboBilling::RefundWriter.money(refund.refund_amount))
    else
      flash[:error] = refund.message
    end
    redirect_to qbo_refund_path(refund)
  rescue RedmineQboBilling::RefundWriter::Error, *QBO_ERRORS => e
    @form.errors.add(:base, qbo_message(e))
    show_form
  end

  def show
    @refund = QboRefund.find_by(id: params[:id])
    return render_404 unless @refund

    @customer = @refund.customer
  end

  # The refund as a PDF, shown in the browser to print or save
  def pdf
    refund = QboRefund.find_by(id: params[:id])
    return render_404 unless refund

    document = RedmineQboBilling::RefundPdf.new(refund)
    send_data document.render, type: 'application/pdf', disposition: 'inline', filename: document.filename
  end

  # Emails the customer the refund's summary (again, or after fixing their email in QuickBooks)
  def email
    refund = QboRefund.find_by(id: params[:id])
    return render_404 unless refund&.done?

    warning = RedmineQboBilling::RefundWriter.email_customer(refund, refund.customer, QboRefundMailer)
    if warning
      flash[:error] = warning
    else
      flash[:notice] = l(:notice_refund_emailed, email: refund.emailed_to)
    end
    redirect_to qbo_refund_path(refund)
  end

  private

  # The estimate's parts (its lines that aren't labor), before tax, for the restocking fee
  def estimate_parts(estimate_id)
    return '' if estimate_id.blank?

    estimate = RedmineQboBilling::RefundGateway.new.estimate(estimate_id)
    estimate ? format('%.2f', RedmineQboBilling::RefundWriter.parts_amount(estimate)) : ''
  rescue *QBO_ERRORS => e
    flash.now[:error] = qbo_message(e)
    ''
  end

  def load_page
    @estimates = RedmineQboBilling::RefundWriter.estimate_choices(@customer)
    @preview = RedmineQboBilling::RefundWriter.preview(@customer, parts: @form.parts_value || BigDecimal('0'))
    @statuses = IssueStatus.sorted.to_a
  rescue *QBO_ERRORS => e
    @preview = nil
    flash.now[:error] = qbo_message(e)
  end

  def show_form
    load_page
    render :new, status: :unprocessable_entity
  end

  def qbo_message(error)
    detail = error.respond_to?(:detail) ? error.detail.to_s : ''
    message = error.message.to_s
    detail.present? && !message.include?(detail) ? "#{message}: #{detail}" : message
  end
end
