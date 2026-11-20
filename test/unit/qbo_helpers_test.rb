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

# RefundGateway's QuickBooks calls, the refund email, and the smaller QuickBooks helpers: the services' query
# string and emailing, invoice lines' LinkedTxn, combined PDFs and attaching invoices to issues
class QboHelpersTest < ActiveSupport::TestCase
  include QboFakeServiceHelper
  fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles, :issues, :trackers,
           :projects_trackers, :issue_statuses, :enabled_modules, :enumerations, :journals, :journal_details

  def setup
    @customer = local_customer
    @fake = install_fake_quickbooks
    stub_local_syncs
    @gateway = RedmineQboBilling::RefundGateway.new
  end

  def payment(id, unapplied, date, lines: [])
    doc = Quickbooks::Model::Payment.new(txn_date: date, total: BigDecimal('500'), unapplied_amount: BigDecimal(unapplied.to_s),
                                         customer_ref: qbo_ref(9101))
    doc.id = id.to_s
    doc.sync_token = 1
    doc.line_items = lines
    doc
  end

  # ---- RefundGateway ----

  def test_unapplied_payments_oldest_first
    @fake.query_results = { 'FROM Payment' => [payment(52, 100, Date.new(2026, 11, 5)), payment(50, 0, Date.new(2026, 11, 1)),
                                               payment(51, 200, Date.new(2026, 11, 2))] }
    assert_equal %w[51 52], @gateway.unapplied_payments(9101).map(&:id)
  end

  def test_apply_payment_keeps_existing_lines
    existing = RedmineQboBilling::RefundGateway.linked_line(BigDecimal('100'), 601, 'Invoice')
    doc = payment(50, 400, Date.new(2026, 11, 1), lines: [existing])
    saved = @gateway.apply_payment(doc, BigDecimal('50'), 601, 'Invoice')
    assert_equal [[BigDecimal('150'), '601']], saved.line_items.map { |l| [l.amount, l.linked_transactions.first.txn_id] }

    saved = @gateway.apply_payment(doc, BigDecimal('25'), 800, 'Expense')
    assert_equal [%w[601 Invoice], %w[800 Expense]], saved.line_items.map { |l| [l.linked_transactions.first.txn_id, l.linked_transactions.first.txn_type] }
    assert_equal BigDecimal('500'), saved.total
  end

  def test_payment_method_ids
    RedmineQboBilling::PaymentWriter.stubs(:payment_methods).returns([%w[Cash 1], ['Cheque', '2'], ['Visa', '3']])
    assert_equal '2', @gateway.payment_method_id(:check)
    assert_equal '3', @gateway.payment_method_id(:card)
  end

  def test_account_and_balance
    @fake.query_results = { "AccountType = 'Bank'" => [Quickbooks::Model::Account.new(id: 35)] }
    assert_equal '35', @gateway.account_id('Bank')
    assert_nil @gateway.account_id('Accounts Receivable')
    @fake.customers['9101'] = Quickbooks::Model::Customer.new(balance: BigDecimal('-120'))
    assert_equal BigDecimal('-120'), @gateway.customer_balance(9101)
  end

  def test_reject_estimate_and_documents
    estimate = @fake.add(qbo_estimate(status: 'Pending', lines: [qbo_sales_line(1, 10, 'Labor', 1, 100)]))
    assert_equal estimate, @gateway.estimate(598)
    @gateway.reject_estimate(estimate)
    assert_equal 'Rejected', @fake.updated.last.txn_status
    invoice = @gateway.create_invoice(qbo_invoice(id: nil))
    assert_equal invoice, @gateway.invoice(invoice.id)
  end

  def test_syncs_never_raise
    InvoiceSyncService.any_instance.stubs(:sync_by_id).raises(StandardError)
    PaymentSyncService.any_instance.stubs(:sync_by_id).raises(StandardError)
    EstimateSyncService.any_instance.stubs(:sync_by_id).raises(StandardError)
    assert_nothing_raised do
      @gateway.sync_invoice(1)
      @gateway.sync_payment(1)
      @gateway.sync_estimate(1)
    end
  end

  # ---- refund email ----

  def refund
    QboRefund.create!(customer_id: 9101, method: 'check', check_number: '5001', status: 'done', refund_amount: 407.6,
                      txn_date: Date.new(2026, 11, 16), reason: 'Canceled', kind: 'credit')
  end

  def test_refund_email
    with_settings app_title: 'Test Shop', mail_from: 'shop@example.com' do
      mail = QboRefundMailer.refund_summary(refund, 'jane@example.com')
      assert_equal ['jane@example.com'], mail.to
      assert_equal ['shop@example.com'], mail.from
      assert_match '$407.60', mail.subject
      assert_match 'Test Shop', mail.subject
    end
  end

  def test_refund_email_when_delivery_is_off
    ActionMailer::Base.stubs(:perform_deliveries).returns(false)
    assert_raises(QboRefundMailer::DeliveryOff) { QboRefundMailer.refund_summary(refund, 'jane@example.com').message }
  end

  def test_refund_pdf
    record = refund
    pdf = RedmineQboBilling::RefundPdf.new(record)
    assert pdf.render.start_with?('%PDF')
    assert_equal 'refund-2026-11-16-jane-customer.pdf', pdf.filename
    assert_match 'Jane Customer', pdf.title
  end

  # ---- QuickBooks service helpers ----

  def access_token
    OAuth2::AccessToken.new(OAuth2::Client.new('key', 'secret', site: 'https://appcenter.intuit.com'), 'token')
  end

  def test_services_ask_for_every_custom_field
    service = RedmineQboBilling::QboEstimateService.new(company_id: '1', access_token: access_token)
    url = service.send(:add_query_string_to_url, 'https://quickbooks.example/v3/estimate', { 'query' => 'x' })
    assert_match 'minorversion=75', url
    assert_match 'include=enhancedAllCustomFields', url
    assert_match 'query=x', url
    assert_match '&include', service.send(:add_query_string_to_url, 'https://quickbooks.example/v3/estimate?a=1')
  end

  def test_send_document
    service = RedmineQboBilling::QboInvoiceService.new(company_id: '1', access_token: access_token)
    sent_url = nil
    response = Struct.new(:code, :plain_body).new(200, '<IntuitResponse><Invoice><Id>601</Id></Invoice></IntuitResponse>')
    service.define_singleton_method(:do_http_post) { |url, *_args| sent_url = url; response }
    service.define_singleton_method(:parse_singular_entity_response) { |_model, body| body[/<Invoice>.*<\/Invoice>/m] }
    invoice = service.send_invoice(601, 'jane+x@example.com')
    assert_equal '601', invoice.id
    assert_match '/invoice/601/send?sendTo=jane%2Bx%40example.com', sent_url

    service.define_singleton_method(:do_http_post) { |*_args| Struct.new(:code).new(400) }
    assert_nil service.send_invoice(601)
  end

  def test_invoice_lines_carry_linked_transactions_after_the_amount
    line = Quickbooks::Model::InvoiceLineItem.new
    line.amount = BigDecimal('120')
    line.linked_transactions = [qbo_link('TimeActivity', 77)]
    line.sales_item! { |d| d.quantity = 1 }
    xml = line.to_xml.to_s
    assert_operator xml.index('<Amount>'), :<, xml.index('<LinkedTxn>')
    assert_operator xml.index('<LinkedTxn>'), :<, xml.index('<SalesItemLineDetail>')
    # Applying again changes nothing
    RedmineQboBilling::Patches::InvoiceLineItemLinkedTxn.apply!
    assert_equal xml, line.to_xml.to_s
  end

  def test_combined_pdf
    page = CombinePDF.new.tap { |p| p << CombinePDF.create_page }.to_pdf
    @fake.add(qbo_invoice(id: 601, doc_number: '1234'))
    @fake.add(qbo_invoice(id: 602, doc_number: '1235'))
    @fake.pdf_body = page
    pdf, ref = PdfService.new(entity: Invoice).fetch_pdf(doc_ids: %w[601 602])
    assert_equal '1234 1235', ref
    assert_equal 2, CombinePDF.parse(pdf).pages.size
    assert_raises(RuntimeError) { PdfService.new(entity: nil) }
  end

  # ---- invoices attached to issues ----

  def test_invoice_attaches_to_its_customers_issues_once
    Invoice.where(id: 601).delete_all
    invoice = Invoice.create!(id: 601, doc_number: '1234', customer_id: 9101, txn_date: Date.new(2026, 11, 12))
    Issue.find(1).update_column(:customer_id, 9101)
    Issue.find(2).update_column(:customer_id, 424_242)
    remote = qbo_invoice(lines: [qbo_note_line(1, 'Install #1: lift, see #2 and #99999')])
    remote.private_note = 'Work order #1'
    InvoiceAttachmentService.new(invoice, remote).attach
    assert_equal [invoice], Issue.find(1).invoices.to_a
    assert_empty Issue.find(2).invoices
    journal = Issue.find(1).journals.last
    assert_equal User.anonymous, journal.user
    assert_equal [%w[invoice 601 1234]], journal.details.map { |d| [d.property, d.prop_key, d.value] }

    assert_no_difference('Journal.count') { InvoiceAttachmentService.new(invoice, remote).attach }
  end
end
