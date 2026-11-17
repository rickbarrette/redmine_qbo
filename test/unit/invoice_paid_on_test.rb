#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

require File.expand_path('../test_helper', __dir__)

class InvoicePaidOnTest < ActiveSupport::TestCase
  PaidOn = RedmineQboBilling::InvoicePaidOn

  def setup
    Payment.where(id: [9301, 9302]).delete_all
  end

  def link(type, id)
    link = Quickbooks::Model::LinkedTransaction.new
    link.txn_type = type
    link.txn_id = id.to_s
    link
  end

  def invoice(date: Date.new(2026, 10, 30), total: 2207.99, balance: 0, links: [], tax: nil)
    invoice = Quickbooks::Model::Invoice.new
    invoice.id = '601'
    invoice.txn_date = date
    invoice.total = BigDecimal(total.to_s)
    invoice.balance = BigDecimal(balance.to_s)
    invoice.linked_transactions = links
    if tax
      invoice.txn_tax_detail = Quickbooks::Model::TransactionTaxDetail.new
      invoice.txn_tax_detail.total_tax = BigDecimal(tax.to_s)
    end
    invoice
  end

  def local_payment(id, date)
    payment = Payment.new(id: id, txn_date: date, total_amount: 100)
    payment.skip_qbo_push = true
    payment.save!(validate: false)
  end

  def test_tax
    assert_equal BigDecimal('80.30'), PaidOn.tax(invoice(tax: '80.30'))
    assert_equal BigDecimal('0'), PaidOn.tax(invoice)
  end

  def test_paid_in_full_on_the_last_payment
    local_payment(9301, Date.new(2026, 10, 8))   # deposit before the invoice
    local_payment(9302, Date.new(2026, 11, 3))   # final payment
    remote = invoice(links: [link('Payment', 9301), link('Payment', 9302), link('Estimate', 598)])
    QboConnectionService.expects(:with_qbo_service).never
    assert_equal Date.new(2026, 11, 3), PaidOn.paid_on(remote)
  end

  def test_deposit_before_the_invoice_counts_on_the_invoice_date
    local_payment(9301, Date.new(2026, 10, 8))
    assert_equal Date.new(2026, 10, 30), PaidOn.paid_on(invoice(links: [link('Payment', 9301)]))
  end

  def test_payments_not_synced_and_credit_memos_are_read_from_quickbooks
    memo = Quickbooks::Model::CreditMemo.new
    memo.id = '70'
    memo.txn_date = Date.new(2026, 11, 9)
    service = mock('service')
    service.stubs(:query).returns(stub(entries: [memo]))
    QboConnectionService.expects(:with_qbo_service).with(entity: 'CreditMemo').yields(service).returns([memo])
    assert_equal Date.new(2026, 11, 9), PaidOn.paid_on(invoice(links: [link('CreditMemo', 70)]))
  end

  def test_open_and_voided_invoices_arent_paid
    assert_nil PaidOn.paid_on(invoice(balance: 10))
    assert_nil PaidOn.paid_on(invoice(total: 0))
  end
end
