#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require_dependency 'issue'

module RedmineQbo
  module Patches
    module IssuePatch

      def self.included(base)
        base.extend(ClassMethods)
        base.send(:include, InstanceMethods)

        base.class_eval do
          belongs_to :customer, class_name: 'Customer', foreign_key: :customer_id, optional: true
          belongs_to :customer_token, primary_key: :id
          belongs_to :estimate, primary_key: :id
          has_and_belongs_to_many :invoices
          has_many :line_items, dependent: :destroy
          accepts_nested_attributes_for :line_items, allow_destroy: true

          before_save :titlize_subject
          after_commit :enqueue_billing, on: :update
        end
        
      end

      module ClassMethods

      end

      module InstanceMethods

        # Enqueue a background job to bill the time spent on this issue to the associated customer in Quickbooks, if the issue is closed and has a customer assigned.
        def enqueue_billing
          log "Checking if issue needs to be billed for issue ##{id}"
          return unless closed?
          return unless customer.present?
          return unless assigned_to&.employee_id.present?

          log "Enqueuing billing for issue ##{id}"
          BillIssueTimeJob.perform_later(id)
        end

        # Titlize the subject of the issue before saving to ensure consistent formatting for billing descriptions in Quickbooks
        def titlize_subject
          log "Titlizing subject for issue ##{id}"

          self.subject = subject.split(/\s+/).map do |word|
            if word =~ /[A-Z]/ && word =~ /[0-9]/
              word
            else
              word.capitalize
            end
          end.join(' ')
        end
      end

      # This method is used to generate a shareable token for the customer associated with this issue, which can be used to link the issue to the corresponding customer in Quickbooks for billing and tracking purposes.
      def share_token
        CustomerToken.get_token(self)
      end

      private

      def log(msg)
          Rails.logger.info "[IssuePatch] #{msg}"
      end
    end

    Issue.send(:include, IssuePatch)
  end
end