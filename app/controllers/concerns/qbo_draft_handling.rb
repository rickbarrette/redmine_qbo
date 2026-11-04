#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Drafts on the new estimate and new invoice editors (see QboDraft). "Save draft" keeps what's filled in, even
# if it isn't complete, and reopens it (new?draft_id=). Saving to QuickBooks deletes the draft.
module QboDraftHandling
  extend ActiveSupport::Concern

  private

  # The draft named by draft_id (in the URL, or the editor's hidden field), if the user may open it
  def find_draft(document)
    @draft = (QboDraft.visible.for_document(document).find_by(id: params[:draft_id]) if params[:draft_id].present?)
  end

  # The editor form filled in from a draft, with the details the editor shows but doesn't post
  def form_from_draft(draft)
    form = draft.form
    customer = Customer.find_by(id: form.customer_id) if form.customer_id.present?
    if customer
      form.billing_address = RedmineQboBilling::EstimateWriter.customer_address(customer)
      form.customer_name = customer.name if form.customer_name.blank?
    end
    # Invoices keep the sales person shown on the editor (e.g. from an estimate); estimates are always the user's
    form.sales_person = (draft.invoice? && draft.fields['sales_person'].presence) || User.current.name
    form.lines = form.lines.reject(&:blank?)
    form.lines += Array.new([2 - form.lines.size, 1].max) { RedmineQboBilling::EstimateForm::Line.new(quantity: '', taxable: true) }
    form
  end

  # Saves what's on the editor as a draft (no checks: a draft can be missing anything) and reopens it
  def save_draft(document, fields)
    draft = @draft || QboDraft.new(document: document)
    fields = fields.to_h.stringify_keys
    draft.fields = fields
    draft.customer_id = (Customer.where(id: fields['customer_id']).pick(:id) if fields['customer_id'].present?)
    draft.user = User.current
    draft.save!
    flash[:notice] = l(:notice_qbo_draft_saved)
    redirect_to draft_editor_path(draft)
  end

  # Saved to QuickBooks: the draft isn't needed any more
  def discard_draft
    @draft&.destroy
    @draft = nil
  end

  # A new document for a customer who already has drafts of it: the editor points them out
  def load_customer_drafts(document, customer_id)
    @customer_drafts =
      if @draft.nil? && customer_id.present?
        QboDraft.visible.for_document(document).where(customer_id: customer_id).newest_first.to_a
      else
        []
      end
  end

  # A draft_id that's gone (e.g. finished or deleted by someone else): say so and list the drafts
  def draft_missing
    flash[:error] = l(:error_qbo_draft_not_found)
    redirect_to qbo_drafts_path
  end

  def draft_editor_path(draft)
    draft.invoice? ? new_qbo_invoice_path(draft_id: draft.id) : new_qbo_estimate_path(draft_id: draft.id)
  end
end
