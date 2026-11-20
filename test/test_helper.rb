#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require File.expand_path('../../../test/test_helper', __dir__)
require File.expand_path('qbo_fake_service', __dir__)

module QboRefundTestHelper
  CUSTOMER_ID = 9101

  # Stands in for QuickBooks: the customer's payments, and what the refund made
  class FakeGateway
    attr_reader :payments, :invoices, :purchases, :applied, :rejected, :receipts
    attr_accessor :auto_apply, :fail_on, :estimate_record, :balance

    def initialize(payments: [], estimate: nil)
      @payments = payments
      @estimate_record = estimate
      @invoices = []
      @purchases = []
      @applied = []
      @rejected = []
      @receipts = []
      @auto_apply = false
      @balance = BigDecimal('0')
    end

    def unapplied_payments(_customer_id)
      payments.select { |p| p.unapplied_amount.to_d.positive? }.sort_by { |p| [p.txn_date, p.id.to_i] }
    end

    def estimate(id)
      estimate_record if estimate_record && estimate_record.id.to_s == id.to_s
    end

    def create_invoice(invoice)
      raise Quickbooks::IntuitRequestException, 'QuickBooks is down' if fail_on == :invoice

      invoice.id = (700 + invoices.size).to_s
      invoice.doc_number = (1500 + invoices.size).to_s
      invoice.total = invoice.line_items.sum(BigDecimal('0')) { |l| l.amount.to_d }
      invoice.balance = invoice.total
      invoices << invoice
      # QuickBooks' "Automatically apply credits"
      if auto_apply
        unapplied_payments(nil).each do |p|
          take = [invoice.balance, p.unapplied_amount.to_d].min
          next unless take.positive?

          apply_payment(p, take, invoice.id, 'Invoice')
        end
      end
      invoice
    end

    def invoice(id)
      invoices.find { |i| i.id.to_s == id.to_s }
    end

    def apply_payment(payment, amount, txn_id, txn_type)
      raise Quickbooks::IntuitRequestException, 'Link refused' if fail_on == :link

      payment.unapplied_amount = payment.unapplied_amount.to_d - amount
      invoice(txn_id).balance = invoice(txn_id).balance.to_d - amount if txn_type == 'Invoice'
      applied << [payment.id, amount, txn_id.to_s, txn_type]
      payment
    end

    def create_purchase(purchase)
      raise Quickbooks::IntuitRequestException, 'QuickBooks is down' if fail_on == :purchase

      purchase.id = (800 + purchases.size).to_s
      purchases << purchase
      purchase
    end

    # QuickBooks' refund receipt: tax at 7% on the taxable lines, after the discount's share
    def create_refund_receipt(receipt)
      raise Quickbooks::IntuitRequestException, 'QuickBooks is down' if fail_on == :receipt

      sales = receipt.line_items.select { |l| l.detail_type.to_s == 'SalesItemLineDetail' }
      discount = receipt.line_items.select { |l| l.detail_type.to_s == 'DiscountLineDetail' }.sum(BigDecimal('0')) { |l| l.amount.to_d }
      lines = sales.sum(BigDecimal('0')) { |l| l.amount.to_d.positive? ? l.amount.to_d : 0 }
      taxable = sales.select { |l| l.sales_item_line_detail.tax_code_ref&.value == 'TAX' }.sum(BigDecimal('0')) { |l| l.amount.to_d }
      tax = (taxable * (lines.positive? ? 1 - discount / lines : 1) * BigDecimal('0.07')).round(2)
      receipt.id = (900 + receipts.size).to_s
      receipt.doc_number = (3000 + receipts.size).to_s
      receipt.txn_tax_detail = Quickbooks::Model::TransactionTaxDetail.new
      receipt.txn_tax_detail.total_tax = tax
      receipt.total = sales.sum(BigDecimal('0')) { |l| l.amount.to_d } - discount + tax
      receipts << receipt
      receipt
    end

    def payment_method_id(kind)
      { check: '2', card: '3' }[kind]
    end

    def account_id(type)
      { 'Accounts Receivable' => '84', 'Bank' => '35' }[type]
    end

    def customer_balance(_customer_id)
      balance
    end

    def reject_estimate(estimate)
      rejected << estimate.id.to_s
    end

    def sync_invoice(_id); end
    def sync_payment(_id); end
    def sync_estimate(_id); end
  end

  class FakeMailer
    Delivery = Struct.new(:refund, :email) do
      def deliver_now
        FakeMailer.sent << [refund.id, email]
      end
    end

    def self.sent
      @sent ||= []
    end

    def self.refund_summary(refund, email)
      Delivery.new(refund, email)
    end
  end

  def self.included(base)
    base.fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles, :issues, :trackers,
                  :projects_trackers, :issue_statuses, :enabled_modules, :enumerations, :workflows
    base.setup do
      QboRefund.delete_all
      Customer.where(id: CUSTOMER_ID).delete_all
      FakeMailer.sent.clear
    end
  end

  def create_customer
    customer = Customer.new(id: CUSTOMER_ID, name: 'Jane Customer')
    customer.skip_qbo_push = true
    customer.save!
    customer
  end

  def deposit(id, amount, date: Date.new(2026, 11, 2))
    payment = Quickbooks::Model::Payment.new
    payment.id = id.to_s
    payment.txn_date = date
    payment.total = BigDecimal(amount.to_s)
    payment.unapplied_amount = BigDecimal(amount.to_s)
    payment.customer_ref = Quickbooks::Model::BaseReference.new(CUSTOMER_ID.to_s)
    payment
  end

  def item_line(item_id, name, amount)
    line = Quickbooks::Model::InvoiceLineItem.new
    line.amount = BigDecimal(amount.to_s)
    line.sales_item! { |d| d.item_ref = Quickbooks::Model::BaseReference.new(item_id.to_s, name: name) }
    line
  end

  # E1068: $1,900 labor and $307.99 of parts
  def estimate(id: 598, status: 'Accepted', customer_id: CUSTOMER_ID)
    estimate = Quickbooks::Model::Estimate.new
    estimate.id = id.to_s
    estimate.doc_number = '1068'
    estimate.txn_status = status
    estimate.customer_ref = Quickbooks::Model::BaseReference.new(customer_id.to_s)
    estimate.line_items = [item_line(1, 'Labor', 1900), item_line(2, 'TF HD JK Ball Joints', '307.99')]
    estimate
  end

  def fee_item
    Struct.new(:id, :name).new('55', 'Restocking Fee')
  end

  def sales_line(id, item_id, name, quantity, rate, taxable: true, description: '')
    line = Quickbooks::Model::InvoiceLineItem.new
    line.id = id.to_s
    line.description = description
    line.amount = (BigDecimal(quantity.to_s) * BigDecimal(rate.to_s)).round(2)
    line.sales_item! do |d|
      d.item_ref = Quickbooks::Model::BaseReference.new(item_id.to_s, name: name)
      d.quantity = BigDecimal(quantity.to_s)
      d.unit_price = BigDecimal(rate.to_s)
      d.tax_code_ref = Quickbooks::Model::BaseReference.new(taxable ? 'TAX' : 'NON')
    end
    line
  end

  # Invoice #1234, paid in full: 2 h labor at $120 (not taxed), 4 brake pads at $30 and a $80 rotor (taxed at
  # 7%: $14.00), $454.00 in all
  def paid_invoice(id: 950, balance: 0, customer_id: CUSTOMER_ID, discount: nil)
    invoice = Quickbooks::Model::Invoice.new
    invoice.id = id.to_s
    invoice.doc_number = '1234'
    invoice.txn_date = Date.new(2026, 11, 2)
    invoice.customer_ref = Quickbooks::Model::BaseReference.new(customer_id.to_s)
    invoice.line_items = [sales_line(1, 1, 'Labor', 2, 120, taxable: false, description: 'Brake job'),
                          sales_line(2, 3, 'Brake Pads', 4, 30, description: 'Ceramic pads'),
                          sales_line(3, 4, 'Rotor', 1, 80, description: 'Front rotor')]
    tax = BigDecimal('14')
    if discount
      line = Quickbooks::Model::InvoiceLineItem.new
      line.amount = BigDecimal(discount.to_s)
      line.discount_item! { |d| d.percent_based = false }
      invoice.line_items = invoice.line_items + [line]
      tax = (BigDecimal('200') * (1 - BigDecimal(discount.to_s) / 440) * BigDecimal('0.07')).round(2)
    end
    invoice.txn_tax_detail = Quickbooks::Model::TransactionTaxDetail.new
    invoice.txn_tax_detail.total_tax = tax
    invoice.total = BigDecimal('440') - BigDecimal((discount || 0).to_s) + tax
    invoice.balance = BigDecimal(balance.to_s)
    invoice
  end

  def invoice_refund_form(attributes = {})
    form = RedmineQboBilling::InvoiceRefundForm.from_params(
      { customer_id: CUSTOMER_ID.to_s, invoice_id: '950', txn_date: '2026-11-18', method: 'check',
        check_number: '5002', reason: 'Parts returned unused', charge_fee: '1', note_issues: '1',
        email_customer: '1', lines: { '2' => { refund: '1', quantity: '4' }, '3' => { refund: '1', quantity: '1' } } }
        .merge(attributes)
    )
    form
  end

  def refund_form(attributes = {})
    RedmineQboBilling::RefundForm.new({ customer_id: CUSTOMER_ID.to_s, estimate_id: '598', txn_date: '2026-11-16',
                                        parts_amount: '307.99', method: 'check', check_number: '5001',
                                        reason: 'Customer canceled the order', close_estimate: '1',
                                        cancel_issues: '1', email_customer: '1' }.merge(attributes))
  end
end
