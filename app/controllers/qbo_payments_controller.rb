#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Receives customer payments in QuickBooks: payment type and amount, applied to open invoices oldest first, or
# saved as a deposit. A saved payment can be printed (QuickBooks' payment PDF). A customer's payments are
# listed on their payments page.
class QboPaymentsController < ApplicationController

  before_action :authorize_global, except: :sync
  before_action :require_admin, only: :sync

  QBO_ERRORS = QboEstimatesController::QBO_ERRORS

  # Re-reads every payment from QuickBooks into the local cache (admin, from the plugin settings)
  def sync
    Payment.sync
    redirect_back fallback_location: home_path, flash: { notice: I18n.t(:label_syncing) }
  end

  # The customer's payments, newest first, read from QuickBooks
  def index
    @customer = Customer.find_by(id: params[:customer_id])
    return render_404 unless @customer

    @payments = RedmineQboBilling::PaymentWriter.customer_payments(@customer)
    @totals = RedmineQboBilling::PaymentWriter.payment_totals(@payments)
  rescue *QBO_ERRORS => e
    @payments = []
    @totals = RedmineQboBilling::PaymentWriter.payment_totals([])
    flash.now[:error] = qbo_message(e)
  end

  def new
    customer = Customer.find_by(id: params[:customer_id]) if params[:customer_id].present?
    @form = RedmineQboBilling::PaymentWriter.new_form(customer: customer, user: User.current)
    load_choices
  end

  def create
    @form = RedmineQboBilling::PaymentForm.from_params(payment_params)
    return show_form unless @form.valid?

    payment = RedmineQboBilling::PaymentWriter.save(@form)
    flash[:notice] = l(:notice_payment_saved, amount: view_context.number_to_currency(payment.total))
    redirect_to qbo_payment_path(payment.id)
  rescue *QBO_ERRORS => e
    logger.warn "[RedmineQboBilling] #{e.class}: #{qbo_message(e)}"
    @form.errors.add(:base, qbo_message(e))
    show_form
  end

  def show
    @payment = RedmineQboBilling::PaymentWriter.load(params[:id])
    @customer = Customer.find_by(id: @payment.customer_ref&.value)
  rescue *QBO_ERRORS => e
    flash[:error] = qbo_message(e)
    redirect_back_or_default home_path
  end

  # QuickBooks' PDF of the payment, shown in the browser to print
  def pdf
    data = RedmineQboBilling::PaymentWriter.pdf(params[:id])
    send_data data, type: 'application/pdf', disposition: 'inline', filename: "payment-#{params[:id].to_i}.pdf"
  rescue *QBO_ERRORS => e
    flash[:error] = qbo_message(e)
    redirect_to qbo_payment_path(params[:id])
  end

  # The customer's open invoices, oldest first, so the page can show how the payment will be applied
  def open_invoices
    customer = Customer.find_by(id: params[:customer_id])
    return render(json: [], status: :not_found) unless customer

    render json: RedmineQboBilling::PaymentWriter.open_invoices(customer)
  rescue *QBO_ERRORS => e
    render json: { error: qbo_message(e) }, status: :unprocessable_entity
  end

  private

  def payment_params
    params.require(:payment).permit(*RedmineQboBilling::PaymentForm::ATTRIBUTES, invoice_ids: [])
  end

  def load_choices
    @payment_methods = RedmineQboBilling::PaymentWriter.payment_methods
    customer = Customer.find_by(id: @form.customer_id) if @form.customer_id.present?
    @open_invoices = customer ? RedmineQboBilling::PaymentWriter.open_invoices(customer) : []
  rescue *QBO_ERRORS => e
    @open_invoices = []
    flash.now[:error] = qbo_message(e)
  end

  def show_form
    load_choices
    render :new, status: :unprocessable_entity
  end

  def qbo_message(error)
    detail = error.respond_to?(:detail) ? error.detail.to_s : ''
    message = error.message.to_s
    detail.present? && !message.include?(detail) ? "#{message}: #{detail}" : message
  end
end
