#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class InvoiceCustomFieldSyncService

  def initialize(issue, invoice, remote)
    @issue   = issue
    @invoice = invoice
    @remote = remote
  end

  # Sync custom fields on the issue based on the invoice data, then push changes to QBO if any fields were updated
  def sync
    return if @invoice.qbo_sync_locked?

    log "Syncing custom fields for issue ##{@issue.id} based on invoice ##{@invoice.doc_number}"

    changed = false

    # Process Invoice Custom Fields via Hooks
    Redmine::Hook.call_hook(
      :process_invoice_custom_fields,
      issue: @issue,
      invoice: @remote
    ).each do |context|
        next unless context
        changed ||= context[:is_changed]
        log "Custom fields updated by hook, marking invoice for push to QBO" if context[:is_changed]
    end

    # Process Issue Custom Values from any issue custom fields that match the invoice custom fields
    begin
      value = @issue.custom_values.find_by(custom_field_id: CustomField.find_by_name(cf.name).id)
      
      # Check to see if the value is blank...
      if not value.value.to_s.blank?
        # Check to see if the value is diffrent
        if not cf.string_value.to_s.eql? value.value.to_s
          # update the custom field on the invoice
          cf.string_value = value.value.to_s
          is_changed = true
        end
      end
    rescue
      # Nothing to do here, there is no match
    end

    push_if_changed if changed
  end

  private

  # If any custom fields were changed during the sync process, this method will trigger a push of the invoice data to QuickBooks Online to ensure that the remote data stays in sync with the local changes. It uses the InvoicePushService to handle the actual communication with QBO.
  def push_if_changed
    InvoicePushService.new(@invoice).push
  end

  def log(msg)
    Rails.logger.info "[InvoiceCustomFieldSyncService] #{msg}"
  end
  
end