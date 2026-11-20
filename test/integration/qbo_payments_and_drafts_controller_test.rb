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

class QboPaymentsAndDraftsControllerTest < Redmine::IntegrationTest
  include QboEditorTestHelper

  def setup
    Invoice.where(id: 601).delete_all
    @fake.query_results = { 'FROM Invoice' => [invoice_doc(balance: '240')], 'PaymentMethod' => [
      Quickbooks::Model::PaymentMethod.new(id: 2, name: 'Check', active: true)
    ] }
  end

  def payment_params(extra = {})
    { customer_id: '9101', txn_date: '2026-11-20', payment_method_id: '2', amount: '100' }.merge(extra)
  end

  def saved_payment
    doc = Quickbooks::Model::Payment.new(customer_ref: qbo_ref(9101, 'Jane Customer'), txn_date: Date.new(2026, 11, 20),
                                         total: BigDecimal('100'), payment_method_ref: qbo_ref(2, 'Check'))
    doc.id = '801'
    doc.sync_token = 1
    doc.line_items = [Quickbooks::Model::Line.new.tap { |l| l.amount = BigDecimal('100'); l.invoice_id = '601' }]
    @fake.add(doc)
  end

  def test_receiving_needs_receive_payments
    login_with(:view_payments)
    get '/qbo_payments/new'
    assert_response :forbidden
    post '/qbo_payments', params: { payment: payment_params }
    assert_response :forbidden
    get '/qbo_payments', params: { customer_id: 9101 }
    assert_response :success
  end

  def test_receive_a_payment
    login_with(:receive_payments)
    get '/qbo_payments/new', params: { customer_id: 9101 }
    assert_response :success
    post '/qbo_payments', params: { payment: payment_params }
    payment = @fake.created.first
    assert_redirected_to "/qbo_payments/#{payment.id}"
    assert_equal BigDecimal('100'), payment.line_items.first.amount
  end

  def test_invalid_payment
    login_with(:receive_payments)
    post '/qbo_payments', params: { payment: payment_params(amount: '0') }
    assert_response :unprocessable_entity
    assert_empty @fake.created
  end

  def test_show_edit_update_pdf
    login_with(:receive_payments)
    saved_payment
    get '/qbo_payments/801'
    assert_response :success
    get '/qbo_payments/801/edit'
    assert_response :success
    patch '/qbo_payments/801', params: { payment: payment_params(sync_token: '1', invoice_ids: ['601'], memo: 'Edited') }
    assert_redirected_to '/qbo_payments/801'
    assert_equal 'Edited', @fake.updated.first.private_note
    @fake.pdf_body = '%PDF-1.4'
    get '/qbo_payments/801/pdf'
    assert_equal 'application/pdf', response.media_type
  end

  def test_stale_payment_update
    login_with(:receive_payments)
    saved_payment
    patch '/qbo_payments/801', params: { payment: payment_params(sync_token: '0') }
    assert_response :unprocessable_entity
  end

  def test_missing_payment
    login_with(:view_payments)
    get '/qbo_payments/999'
    assert_response :redirect
    assert_equal I18n.t(:notice_payment_not_found), flash[:error]
  end

  def test_open_invoices
    login_with(:receive_payments)
    get '/qbo_payments/open_invoices', params: { customer_id: 9101 }
    assert_equal ['601'], JSON.parse(response.body).map { |i| i['id'] }
    get '/qbo_payments/open_invoices', params: { customer_id: 424_242 }
    assert_response :not_found
  end

  def test_payment_sync_is_admin_only
    login_with(:receive_payments)
    get '/qbo_payments/sync'
    assert_response :forbidden
  end

  # ---- drafts ----

  def test_drafts_by_permission
    estimate = QboDraft.create!(document: 'estimate', fields: { 'customer_name' => 'Est Draft' })
    invoice = QboDraft.create!(document: 'invoice', fields: { 'customer_name' => 'Inv Draft' })
    login_with(:view_customers)
    get '/qbo_drafts'
    assert_response :forbidden

    login_with(:write_estimates)
    get '/qbo_drafts'
    assert_response :success
    assert_select 'body', text: /Est Draft/
    assert_select 'body', text: /Inv Draft/, count: 0

    # Not allowed to delete an invoice draft
    delete "/qbo_drafts/#{invoice.id}"
    assert QboDraft.exists?(invoice.id)
    assert_equal I18n.t(:error_qbo_draft_not_found), flash[:error]

    delete "/qbo_drafts/#{estimate.id}"
    assert_not QboDraft.exists?(estimate.id)
  end
end
