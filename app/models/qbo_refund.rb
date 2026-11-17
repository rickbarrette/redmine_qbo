#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# A customer refund (SOP-OPS-014), as it was made: the restocking fee, the refund, and each step's outcome
class QboRefund < ApplicationRecord
  METHODS = %w[check card].freeze
  STATUSES = %w[done incomplete].freeze

  belongs_to :customer
  belongs_to :user, optional: true

  validates :customer_id, presence: true
  validates :method, inclusion: { in: METHODS }
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(created_at: :desc, id: :desc) }

  def done?
    status == 'done'
  end

  def check?
    method == 'check'
  end

  def method_name
    I18n.t("label_refund_method_#{method}")
  end

  def canceled_issue_ids
    Array(JSON.parse(self[:canceled_issue_ids].presence || '[]')).map(&:to_i)
  rescue JSON::ParserError
    []
  end

  def canceled_issue_ids=(ids)
    self[:canceled_issue_ids] = Array(ids).map(&:to_i).uniq.to_json
  end

  # The QuickBooks screen for the refund check or expense
  def purchase_url
    return nil if purchase_id.blank?

    page = check? ? 'check' : 'expense'
    "https://#{RedmineQbo.sandbox_mode? ? 'sandbox' : 'app'}.qbo.intuit.com/app/#{page}?txnId=#{purchase_id}"
  end
end
