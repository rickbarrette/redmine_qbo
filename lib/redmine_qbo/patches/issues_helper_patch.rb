#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module RedmineQbo
  module Patches
    # Shows the customer and estimate by name, and invoices attached by the QuickBooks webhook, in an
    # issue's history, emails and PDF. Redmine records the customer and estimate by id, like its own
    # fields, but only looks up names for the fields it knows about. The ids stay in the database, so
    # existing history entries show names too.
    module IssuesHelperPatch
      JOURNAL_NAMED_FIELDS = { 'customer_id' => 'Customer', 'estimate_id' => 'Estimate' }.freeze

      def show_detail(detail, no_html = false, options = {})
        return qbo_invoice_detail(detail, no_html, options) if detail.property == 'invoice'

        model = detail.property == 'attr' && JOURNAL_NAMED_FIELDS[detail.prop_key]
        return super unless model

        # Hand Redmine a copy with names in place of ids, so it formats it like any other change
        named = JournalDetail.new(property: detail.property, prop_key: detail.prop_key,
                                  old_value: qbo_journal_name(model, detail.old_value),
                                  value: qbo_journal_name(model, detail.value))
        named.id = detail.id
        named.journal_id = detail.journal_id
        super(named, no_html, options)
      end

      private

      # "Invoice 1042 added", recorded when the QuickBooks webhook attaches an invoice to the issue
      # (see InvoiceAttachmentService). The number links to the invoice PDF while the invoice exists.
      def qbo_invoice_detail(detail, no_html, options)
        label = l(:field_invoice)
        value = detail.value
        old_value = detail.old_value

        unless no_html
          label = content_tag('strong', label)
          if value.present?
            value = Invoice.exists?(detail.prop_key) ? link_to(value, invoice_url(detail.prop_key, only_path: options[:only_path] != false)) : content_tag('i', value)
          end
          old_value = content_tag('del', content_tag('i', old_value)) if old_value.present?
        end

        if detail.value.present?
          l(:text_journal_added, label: label, value: value).html_safe
        else
          l(:text_journal_deleted, label: label, old: old_value).html_safe
        end
      end

      # The record's name, or the id when it no longer exists. Cached for the request, since a
      # history can mention the same customer many times.
      def qbo_journal_name(model, id)
        return id if id.blank?

        @qbo_journal_names ||= {}
        @qbo_journal_names[[model, id]] ||= model.constantize.find_by(id: id)&.to_s.presence || id
      end
    end
  end
end
