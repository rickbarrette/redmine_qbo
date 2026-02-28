#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class CustomerToken < ApplicationRecord
  belongs_to :issue

  validates :issue_id, presence: true
  validates :token, presence: true, uniqueness: true

  before_validation :generate_token, on: :create
  before_validation :generate_expire_date, on: :create

  scope :active, -> { where("expires_at > ?", Time.current) }

  TOKEN_EXPIRATION = 1.month

  # Check if the token has expired
  def expired?
    expires_at.present? && expires_at <= Time.current
  end

  # Remove expired tokens from the database
  def self.remove_expired_tokens
    where("expires_at <= ?", Time.current).delete_all
  end

  # Get or create a token for the given issue
  def self.get_token(issue)
    return unless issue
    return unless User.current.allowed_to?(:view_issues, issue.project)

    token = active.find_by(issue_id: issue.id)
    return token if token

    create!(issue: issue)
  end

  private

  # Generate a unique token for the customer
  def generate_token
    self.token ||= SecureRandom.urlsafe_base64(32)
  end

  # Generate an expiration date for the token
  def generate_expire_date
    self.expires_at ||= Time.current + TOKEN_EXPIRATION
  end
end