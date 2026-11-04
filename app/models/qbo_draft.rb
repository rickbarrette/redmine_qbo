#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# A new estimate or invoice saved part way, in Redmine only. Nothing is in QuickBooks until it's saved from
# the editor, so QuickBooks can't apply a deposit to an invoice that's still being written. Drafts are shared:
# anyone with Write estimates (or Write invoices) can continue or delete any estimate (or invoice) draft.
class QboDraft < ApplicationRecord
  DOCUMENTS = %w[estimate invoice].freeze

  belongs_to :customer, optional: true
  # Who saved it last
  belongs_to :user, optional: true

  validates :document, inclusion: { in: DOCUMENTS }

  scope :newest_first, -> { order(updated_at: :desc, id: :desc) }
  scope :for_document, ->(document) { where(document: document.to_s) }

  # The drafts a user may open: estimate drafts need Write estimates, invoice drafts Write invoices
  scope :visible, lambda { |user = User.current|
    documents = []
    documents << 'estimate' if RedmineQboBilling.writer?(user)
    documents << 'invoice' if RedmineQboBilling.invoice_writer?(user)
    where(document: documents)
  }

  def self.writable_document?(document, user = User.current)
    case document.to_s
    when 'estimate' then RedmineQboBilling.writer?(user)
    when 'invoice' then RedmineQboBilling.invoice_writer?(user)
    else false
    end
  end

  # The editor's fields as posted (estimate[...])
  def fields
    parsed = JSON.parse(data.presence || '{}')
    parsed.is_a?(Hash) ? parsed : {}
  rescue JSON::ParserError
    {}
  end

  def fields=(hash)
    self.data = hash.to_h.to_json
  end

  # The editor form, filled in as it was saved
  def form
    RedmineQboBilling::EstimateForm.from_params(fields, document: document)
  end

  def invoice?
    document == 'invoice'
  end

  def customer_name
    customer&.name.presence || fields['customer_name'].presence
  end

  def subtotal
    form.subtotal
  end

  def line_count
    form.filled_lines.count { |line| !line.subtotal? }
  end
end
