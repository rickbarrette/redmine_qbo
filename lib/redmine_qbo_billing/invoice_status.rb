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
  # An invoice's status, worked out from its total, balance and due date the way QuickBooks' invoice list
  # shows it (QuickBooks keeps no status field on invoices):
  #   :voided  - nothing to pay at all (a voided invoice has a zero total)
  #   :paid    - nothing left owing
  #   :partial - some of it paid
  #   :overdue - money owing and past the due date
  #   :open    - money owing, not yet due
  # nil when the balance isn't known (e.g. an invoice synced before balances were kept).
  module InvoiceStatus
    STATUSES = %i[voided paid partial overdue open].freeze

    module_function

    def status(total:, balance:, due_date: nil, today: Date.current)
      return nil if balance.nil? || balance.to_s.strip.empty?

      total = to_d(total)
      balance = to_d(balance)
      return :voided if total.zero? && balance.zero?
      return :paid if balance <= 0
      return :overdue if due_date && due_date < today
      balance < total ? :partial : :open
    end

    def label(status)
      status ? I18n.t("label_invoice_status_#{status}") : ''
    end

    def to_d(value)
      BigDecimal(value.to_s.presence || '0')
    rescue ArgumentError
      BigDecimal('0')
    end
  end
end
