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

class QboRefundsTest < Redmine::IntegrationTest
  include QboRefundTestHelper

  def setup
    @customer = create_customer
    Customer.any_instance.stubs(:email).returns('jane@example.com')
    RedmineQboBilling::RefundWriter.stubs(:fee_item).returns(fee_item)
    @gateway = FakeGateway.new(payments: [deposit(50, 500)], estimate: estimate)
    RedmineQboBilling::RefundGateway.stubs(:new).returns(@gateway)
    RedmineQboBilling::RefundWriter.stubs(:estimate_choices).returns([['E1068 · 2026-10-06', '598']])
    QboRefundMailer.stubs(:refund_summary).returns(stub(deliver_now: true))
  end

  def test_needs_the_permission
    log_user('jsmith', 'jsmith')
    get "/qbo_refunds/new?customer_id=#{CUSTOMER_ID}"
    assert_response :forbidden

    Role.find(1).add_permission!(:issue_refunds)
    get "/qbo_refunds/new?customer_id=#{CUSTOMER_ID}"
    assert_response :success
  end

  def test_refund_page_fills_in_the_estimates_parts
    log_user('admin', 'admin')
    get "/qbo_refunds/new?customer_id=#{CUSTOMER_ID}&estimate_id=598"
    assert_response :success
    assert_select 'input[name=?][value=?]', 'refund[parts_amount]', '307.99'
    assert_select '#qbo-refund-credit', text: '$500.00'
    assert_select '#qbo-refund-fee', text: '-$92.40'
    assert_select '#qbo-refund-amount', text: '$407.60'
    assert_select 'input[name=?][value=check][checked]', 'refund[method]'
  end

  def test_refund
    log_user('admin', 'admin')
    post '/qbo_refunds', params: { refund: { customer_id: CUSTOMER_ID, estimate_id: '598', parts_amount: '307.99',
                                             method: 'check', check_number: '5001', txn_date: '2026-11-16',
                                             reason: 'Canceled', close_estimate: '1', cancel_issues: '0', email_customer: '1' } }
    refund = QboRefund.last
    assert_redirected_to "/qbo_refunds/#{refund.id}"
    assert refund.done?, refund.message
    assert_equal BigDecimal('407.60'), refund.refund_amount
    follow_redirect!
    assert_select 'p', text: /\$407\.60 · Company check #5001/
    assert_select 'a[href*="app/check?txnId="]'
    assert_select 'a[href=?]', "/qbo_invoices/#{refund.fee_invoice_id}/edit"
    assert_select 'a[href=?]', '/qbo_estimates/598/edit'
    assert_select 'a[href*="app/invoice?txnId="]', count: 0

    get "/customers/#{CUSTOMER_ID}"
    assert_select 'a[href=?]', "/qbo_refunds/#{refund.id}"
  end

  def test_form_errors
    log_user('admin', 'admin')
    post '/qbo_refunds', params: { refund: { customer_id: CUSTOMER_ID, parts_amount: '10', method: 'check',
                                             check_number: '', txn_date: '2026-11-16', reason: '' } }
    assert_response :unprocessable_entity
    assert_select '#errorExplanation', text: /check number/
    assert_select '#errorExplanation', text: /reason/
    assert_equal 0, QboRefund.count
  end

  def test_email_again
    log_user('admin', 'admin')
    refund = QboRefund.create!(customer_id: CUSTOMER_ID, method: 'check', check_number: '5001', status: 'done',
                               refund_amount: 100, txn_date: Date.new(2026, 11, 16))
    post "/qbo_refunds/#{refund.id}/email"
    assert_redirected_to "/qbo_refunds/#{refund.id}"
    assert_equal 'jane@example.com', refund.reload.emailed_to
  end

  def test_pdf
    log_user('admin', 'admin')
    refund = QboRefund.create!(customer_id: CUSTOMER_ID, method: 'check', check_number: '5001', status: 'done',
                               estimate_number: '1068', reason: 'Canceled', parts_amount: 307.99, fee_rate: 30,
                               fee_amount: 92.40, fee_invoice_number: '1502', credit_amount: 500, refund_amount: 407.60,
                               balance_after: 0, txn_date: Date.new(2026, 11, 16), user_id: 1)
    get "/qbo_refunds/#{refund.id}/pdf"
    assert_response :success
    assert_equal 'application/pdf', response.media_type
    assert response.body.start_with?('%PDF')
    assert_match(/refund-2026-11-16-jane-customer\.pdf/, response.headers['Content-Disposition'])

    get "/qbo_refunds/#{refund.id}"
    assert_select 'a[href=?]', "/qbo_refunds/#{refund.id}/pdf"
  end

  # ---- Paid invoices ----

  def invoice_setup
    RedmineQboBilling::LaborItems.stubs(:ids).returns([])
    @gateway.invoices << paid_invoice
  end

  def test_invoice_refund_page
    invoice_setup
    log_user('admin', 'admin')
    get '/qbo_refunds/new_invoice?invoice_id=950'
    assert_response :success
    assert_select 'h2', text: /Invoice #1234/
    assert_select 'input[type=checkbox][name=?][checked]', 'refund[lines][2][refund]'
    assert_select 'input[name=?][value=?]', 'refund[lines][2][quantity]', '4'
    assert_select 'input[name=?][value=?]', 'refund[lines][3][amount]', '80.00'
    assert_select 'input[name=?][checked]', 'refund[charge_fee]'
    # Everything ticked: $440.00 of lines, $14.00 tax, 30% of $200.00 parts
    assert_select '#qbo-refund-lines-amount', text: '$440.00'
    assert_select '#qbo-refund-tax', text: '$14.00'
    assert_select '#qbo-refund-fee', text: '-$60.00'
    assert_select '#qbo-refund-amount', text: '$394.00'
  end

  def test_unpaid_invoice_isnt_refunded
    RedmineQboBilling::LaborItems.stubs(:ids).returns([])
    @gateway.invoices << paid_invoice(balance: 50)
    log_user('admin', 'admin')
    get '/qbo_refunds/new_invoice?invoice_id=950'
    assert_redirected_to '/qbo_invoices/950/edit'
  end

  def test_invoice_refund
    invoice_setup
    log_user('admin', 'admin')
    post '/qbo_refunds/create_invoice', params: { refund: {
      customer_id: CUSTOMER_ID, invoice_id: '950', method: 'card', txn_date: '2026-11-18', reason: 'Returned pads',
      charge_fee: '0', note_issues: '1', email_customer: '0',
      lines: { '1' => { refund: '0', quantity: '2', amount: '240.00' }, '2' => { refund: '1', quantity: '2', amount: '60.00' },
               '3' => { refund: '0', quantity: '1', amount: '80.00' } }
    } }
    refund = QboRefund.last
    assert_redirected_to "/qbo_refunds/#{refund.id}"
    assert refund.done?, refund.message
    assert_equal BigDecimal('64.20'), refund.refund_amount
    follow_redirect!
    assert_select 'p', text: /Refund receipt 3000 is recorded/
    assert_select 'a[href*="app/refundreceipt?txnId=900"]'
    assert_select 'a[href=?]', '/qbo_invoices/950/edit'

    get '/qbo_refunds/new_invoice?invoice_id=950'
    assert_select 'input[name=?][value=?]', 'refund[lines][2][quantity]', '2'
    assert_select '.flash.warning a[href=?]', "/qbo_refunds/#{refund.id}"

    get "/qbo_refunds/#{refund.id}/pdf"
    assert_response :success

    get "/customers/#{CUSTOMER_ID}"
    assert_select 'a[href=?]', '/qbo_invoices/950/edit', text: 'Invoice #1234'
  end

  def test_invoice_refund_form_errors
    invoice_setup
    log_user('admin', 'admin')
    post '/qbo_refunds/create_invoice', params: { refund: {
      customer_id: CUSTOMER_ID, invoice_id: '950', method: 'check', check_number: '', txn_date: '2026-11-18', reason: '',
      lines: { '2' => { refund: '1', quantity: '9' } }
    } }
    assert_response :unprocessable_entity
    assert_select '#errorExplanation', text: /check number/
    assert_select '#errorExplanation', text: /reason/

    post '/qbo_refunds/create_invoice', params: { refund: {
      customer_id: CUSTOMER_ID, invoice_id: '950', method: 'check', check_number: '1', txn_date: '2026-11-18', reason: 'x',
      lines: { '2' => { refund: '1', quantity: '9' } }
    } }
    assert_response :unprocessable_entity
    assert_select '#errorExplanation', text: /no more than 4/
    assert_equal 0, QboRefund.count
    assert_empty @gateway.receipts
  end

  def test_credit_refund_page_offers_paid_invoices
    Invoice.where(id: 950).delete_all
    Invoice.new(id: 950, doc_number: '1234', txn_date: Date.new(2026, 11, 2), customer_id: CUSTOMER_ID,
                total_amount: 454, balance: 0).save!(validate: false)
    log_user('admin', 'admin')
    get "/qbo_refunds/new?customer_id=#{CUSTOMER_ID}"
    assert_select '#qbo_refund_invoice option[value="950"]', text: /#1234/
  ensure
    Invoice.where(id: 950).delete_all
  end
end
