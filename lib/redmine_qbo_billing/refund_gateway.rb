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
  # The QuickBooks calls a refund makes (RefundWriter), kept apart so the steps can be tested without QuickBooks.
  class RefundGateway
    # The customer's payments with money not yet applied (deposits and other credit), oldest first
    def unapplied_payments(customer_id)
      payments = with_service('Payment') do |service|
        service.all("SELECT * FROM Payment WHERE CustomerRef = '#{customer_id.to_i}'")
      end
      Array(payments).select { |p| BigDecimal(p.unapplied_amount.to_s.presence || '0').positive? }
                     .sort_by { |p| [p.txn_date || Date.new(1900), p.id.to_i] }
    end

    def estimate(id)
      QboEstimateService.with_service { |service| service.fetch_by_id(id) }
    end

    def create_invoice(invoice)
      with_service('Invoice') { |service| service.create(invoice) }
    end

    def invoice(id)
      with_service('Invoice') { |service| service.fetch_by_id(id) }
    end

    # Applies amount of the payment's unapplied money to a transaction (an invoice, or the refund check or
    # expense). QuickBooks replaces a payment's lines on a sparse update, so its lines are sent back with
    # the new one (added to the line already linked to that transaction, if any). Returns the saved payment.
    def apply_payment(payment, amount, txn_id, txn_type)
      lines = Array(payment.line_items).map { |line| copy_line(line) }
      same = lines.find do |line|
        Array(line.linked_transactions).any? { |t| t.txn_id.to_s == txn_id.to_s && t.txn_type.to_s == txn_type }
      end
      if same
        same.amount = BigDecimal(same.amount.to_s) + amount
      else
        lines << self.class.linked_line(amount, txn_id, txn_type)
      end

      update = Quickbooks::Model::Payment.new
      update.id = payment.id
      update.sync_token = payment.sync_token
      update.customer_ref = payment.customer_ref
      update.total = payment.total
      update.line_items = lines
      with_service('Payment') { |service| service.update(update, sparse: true) }
    end

    def create_purchase(purchase)
      with_service('Purchase') { |service| service.create(purchase) }
    end

    # The first active account of a QuickBooks account type ('Accounts Receivable', 'Bank')
    def account_id(type)
      account = with_service('Account') do |service|
        service.query("SELECT * FROM Account WHERE AccountType = '#{type}' AND Active = true").entries.first
      end
      account&.id&.to_s
    end

    def customer_balance(customer_id)
      customer = with_service('Customer') { |service| service.fetch_by_id(customer_id) }
      BigDecimal(customer&.balance.to_s.presence || '0')
    end

    # Marks the canceled order's estimate Rejected, so it can't be invoiced later
    def reject_estimate(estimate)
      update = EstimateWriter.status_update(estimate, 'Rejected')
      QboEstimateService.with_service { |service| service.update(update, sparse: true) }
    end

    def sync_invoice(id)
      InvoiceSyncService.new.sync_by_id(id)
    rescue StandardError => e
      Rails.logger.warn "[RedmineQboBilling] Could not cache invoice #{id} after a refund: #{e.message}"
    end

    def sync_payment(id)
      PaymentSyncService.new.sync_by_id(id)
    rescue StandardError => e
      Rails.logger.warn "[RedmineQboBilling] Could not cache payment #{id} after a refund: #{e.message}"
    end

    def sync_estimate(id)
      EstimateSyncService.new.sync_by_id(id)
    rescue StandardError => e
      Rails.logger.warn "[RedmineQboBilling] Could not cache estimate #{id} after a refund: #{e.message}"
    end

    def self.linked_line(amount, txn_id, txn_type)
      line = Quickbooks::Model::Line.new
      line.amount = amount
      link = Quickbooks::Model::LinkedTransaction.new
      link.txn_id = txn_id.to_s
      link.txn_type = txn_type
      line.linked_transactions = [link]
      line
    end

    private

    def copy_line(line)
      copy = Quickbooks::Model::Line.new
      copy.amount = BigDecimal(line.amount.to_s)
      copy.linked_transactions = Array(line.linked_transactions).map do |t|
        link = Quickbooks::Model::LinkedTransaction.new
        link.txn_id = t.txn_id
        link.txn_type = t.txn_type
        link
      end
      copy
    end

    def with_service(entity, &block)
      QboConnectionService.with_qbo_service(entity: entity, &block)
    end
  end
end
