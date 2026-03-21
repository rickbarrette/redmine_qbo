#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

module RedmineQbo
  module Patches
    module IssuePatch
      extend ActiveSupport::Concern

      prepended do
        belongs_to :customer, class_name: 'Customer', foreign_key: :customer_id, optional: true
        belongs_to :customer_token, primary_key: :id, optional: true
        belongs_to :estimate, primary_key: :id, optional: true
        has_and_belongs_to_many :invoices

        before_save :titlize_subject
        after_commit :enqueue_billing, on: :update
      end

      # Enqueue a background job to bill the time spent on this issue to QuickBooks if the issue is closed and assigned to an employee
      def enqueue_billing
        log "Checking if issue needs billing for ##{id}"
        return unless closed? && customer.present? && assigned_to&.employee_id.present?

        log "Enqueuing billing for issue ##{id}"
        BillIssueTimeJob.perform_later(id)
      end

      # Titlize the subject for consistent formatting in billing descriptions
      def titlize_subject
        log "Titlizing subject for issue ##{id}"
        self.subject = subject.split(/\s+/).map do |word|
          (word =~ /[A-Z]/ && word =~ /[0-9]/) ? word : word.capitalize
        end.join(' ')
      end

      # Generate a shareable token linking this issue to the customer for QuickBooks
      def share_token
        CustomerToken.get_token(self)
      end

      private

      def log(msg)
        Rails.logger.info "[IssuePatch] #{msg}"
      end
    end
  end
end