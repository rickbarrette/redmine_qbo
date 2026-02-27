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

          before_save :titlize_subject
          after_commit :enqueue_billing, on: :update
        end
      end

      module ClassMethods

      end

      module InstanceMethods

        def enqueue_billing
          Rails.logger.debug "QBO: Checking if issue needs to be billed for issue ##{id}"
          #return unless saved_change_to_status_id?
          return unless closed?
          return unless customer.present?
          return unless assigned_to&.employee_id.present?
          return unless Qbo.first

          Rails.logger.debug "QBO: Enqueuing billing for issue ##{id}"
          BillIssueTimeJob.perform_later(id)
        end

        def titlize_subject
          Rails.logger.debug "QBO: Titlizing subject for issue ##{id}"

          self.subject = subject.split(/\s+/).map do |word|
            if word =~ /[A-Z]/ && word =~ /[0-9]/
              word
            else
              word.capitalize
            end
          end.join(' ')
        end
      end

      def share_token
        CustomerToken.get_token(self)
      end
    end

    Issue.send(:include, IssuePatch)
  end
end