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
  # An invoice's sales tax and the day it was paid in full, worked out from the QuickBooks invoice when it's synced
  # (InvoiceSyncService).
  #
  # An invoice is paid in full on the later of its own date and the dates of the payments and credit memos applied
  # to it, so a deposit taken before the work counts on the day the job was invoiced. The payments' dates come from
  # the local payments (synced from QuickBooks); QuickBooks is only asked for the ones not synced yet and for credit
  # memos.
  module InvoicePaidOn
    APPLIED_TYPES = %w[Payment CreditMemo].freeze
    IDS_PER_QUERY = 100

    module_function

    def tax(remote)
      tax = remote.respond_to?(:txn_tax_detail) ? remote.txn_tax_detail&.total_tax : nil
      tax.nil? ? BigDecimal('0') : BigDecimal(tax.to_s)
    end

    # The day the invoice was paid in full, or nil while it's open (or voided: a $0 total)
    def paid_on(remote, dates: nil)
      return nil unless remote.txn_date
      return nil unless BigDecimal(remote.balance.to_s.presence || '1').zero?
      return nil unless BigDecimal(remote.total.to_s.presence || '0').positive?

      dates ||= applied_dates(applied(remote))
      [remote.txn_date, *applied(remote).map { |type, id| dates[[type, id]] }.compact].max
    end

    # [["Payment", "123"], ...] applied to the invoice
    def applied(remote)
      Array(remote.linked_transactions).select { |link| APPLIED_TYPES.include?(link.txn_type.to_s) }
                                       .map { |link| [link.txn_type.to_s, link.txn_id.to_s] }
    end

    # { ["Payment", "123"] => Date }: local payments first, the rest read from QuickBooks
    def applied_dates(links)
      dates = {}
      payment_ids = links.select { |type, _| type == 'Payment' }.map(&:last)
      Payment.where(id: payment_ids).pluck(:id, :txn_date).each { |id, date| dates[['Payment', id.to_s]] = date if date }
      missing = links.reject { |link| dates.key?(link) }
      missing.group_by(&:first).each do |type, list|
        list.map(&:last).uniq.each_slice(IDS_PER_QUERY) do |ids|
          query = "SELECT * FROM #{type} WHERE Id IN (#{ids.map { |id| "'#{id.gsub(/\D/, '')}'" }.join(',')})"
          records = QboConnectionService.with_qbo_service(entity: type) { |service| service.query(query).entries }
          Array(records).each { |record| dates[[type, record.id.to_s]] = record.txn_date }
        end
      end
      dates
    rescue StandardError => e
      Rails.logger.warn "[RedmineQboBilling] Could not read the dates of what was applied to an invoice: #{e.message}"
      dates
    end
  end
end
