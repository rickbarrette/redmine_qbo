#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Writes, edits and emails QuickBooks invoices from Redmine, with the same editor as estimates, plus importing
# billable time and open estimates. The customer and product searches are QboEstimatesController's.
class QboInvoicesController < ApplicationController

  before_action :authorize_global
  before_action :require_sender_for_save_and_send, only: [:create, :update]
  before_action :find_customer, only: :import_options

  QBO_ERRORS = QboEstimatesController::QBO_ERRORS

  # A blank invoice, or one made from an estimate (?estimate_id=<estimate id>)
  def new
    @form =
      if params[:estimate_id].present?
        RedmineQboBilling::InvoiceWriter.from_estimate(params[:estimate_id], user: User.current)
      else
        customer = Customer.find_by(id: params[:customer_id]) if params[:customer_id].present?
        RedmineQboBilling::InvoiceWriter.new_form(customer: customer, user: User.current)
      end
  rescue *QBO_ERRORS => e
    flash[:error] = qbo_message(e)
    redirect_back_or_default home_path
  end

  def create
    @form = RedmineQboBilling::EstimateForm.from_params(invoice_params, document: 'invoice')
    # Display only (e.g. the estimate's sales person); InvoiceWriter.save works out what's saved
    @form.sales_person = params.dig(:estimate, :sales_person).presence || User.current.name
    return show_invalid(:new) unless @form.valid?

    saved = RedmineQboBilling::InvoiceWriter.save(@form, user: User.current)
    finish_save(saved, l(:notice_invoice_saved_in_quickbooks, number: saved.doc_number))
  rescue *QBO_ERRORS => e
    show_error(e, :new)
  end

  def edit
    @form = RedmineQboBilling::InvoiceWriter.load(params[:id])
  rescue *QBO_ERRORS => e
    flash[:error] = qbo_message(e)
    redirect_back_or_default home_path
  end

  def update
    @form = RedmineQboBilling::EstimateForm.from_params(invoice_params, id: params[:id], document: 'invoice')
    @form.sales_person = params.dig(:estimate, :sales_person).to_s
    return show_invalid(:edit) unless @form.valid?

    saved = RedmineQboBilling::InvoiceWriter.save(@form, user: User.current)
    finish_save(saved, l(:notice_invoice_saved_in_quickbooks, number: saved.doc_number))
  rescue RedmineQboBilling::InvoiceWriter::Conflict => e
    @conflict = true
    show_error(e, :edit)
  rescue *QBO_ERRORS => e
    show_error(e, :edit)
  end

  # Emails an invoice that's already saved (e.g. resending it)
  def send_email
    sent = RedmineQboBilling::InvoiceWriter.send_email(params[:id], params[:email])
    flash[:notice] = l(:notice_invoice_sent, number: sent.doc_number, email: sent.bill_email&.address || params[:email])
    redirect_to edit_qbo_invoice_path(params[:id])
  rescue *QBO_ERRORS => e
    flash[:error] = qbo_message(e)
    redirect_to edit_qbo_invoice_path(params[:id])
  end

  # The customer's billable time and open estimates, for the Import panel
  def import_options
    render json: RedmineQboBilling::InvoiceWriter.import_options(@customer, issue_ids: Array(params[:issue_ids]))
  rescue *QBO_ERRORS => e
    render json: { error: qbo_message(e) }, status: :unprocessable_entity
  end

  private

  def find_customer
    @customer = Customer.find_by(id: params[:customer_id])
    render(json: { error: l(:error_estimate_needs_customer) }, status: :not_found) unless @customer
  end

  def invoice_params
    params.require(:estimate).permit(
      :sync_token, :total_tax, :discount, :email_status, :txn_status, :balance,
      *RedmineQboBilling::EstimateForm::HEADER_ATTRIBUTES,
      linked_estimate_ids: [],
      lines: RedmineQboBilling::EstimateForm::Line::PARAMS
    )
  end

  def save_and_send?
    params[:save_and_send].present?
  end

  def require_sender_for_save_and_send
    deny_access if save_and_send? && !RedmineQboBilling.invoice_sender?
  end

  # After saving: email it if asked, then reopen the saved invoice
  def finish_save(saved, notice)
    if save_and_send?
      begin
        sent = RedmineQboBilling::InvoiceWriter.send_email(saved.id, @form.email)
        notice = l(:notice_invoice_saved_and_sent, number: sent.doc_number, email: sent.bill_email&.address || @form.email)
      rescue *QBO_ERRORS => e
        flash[:error] = l(:error_estimate_saved_not_sent, message: qbo_message(e))
      end
    end
    flash[:notice] = notice
    redirect_to edit_qbo_invoice_path(saved.id)
  end

  def show_error(error, view)
    logger.warn "[RedmineQboBilling] #{error.class}: #{qbo_message(error)}"
    @form.errors.add(:base, qbo_message(error))
    show_invalid(view)
  end

  # Shows the form again with what was typed (see QboEstimatesController#show_invalid)
  def show_invalid(view)
    @form.lines = @form.filled_lines
    customer = Customer.find_by(id: @form.customer_id) if @form.customer_id.present?
    @form.billing_address = RedmineQboBilling::EstimateWriter.customer_address(customer) if customer
    render view, status: :unprocessable_entity
  end

  def qbo_message(error)
    detail = error.respond_to?(:detail) ? error.detail.to_s : ''
    message = error.message.to_s
    detail.present? && !message.include?(detail) ? "#{message}: #{detail}" : message
  end
end
