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

class QboInvoicesControllerTest < Redmine::IntegrationTest
  include QboEditorTestHelper

  def invoice_params(extra = {})
    { customer_id: '9101', txn_date: '2026-11-20', email: 'jane@example.com', lines: line_params }.merge(extra)
  end

  def test_editor_needs_write_invoices
    login_with(:write_estimates)
    get '/qbo_invoices/new'
    assert_response :forbidden
    post '/qbo_invoices', params: { estimate: invoice_params }
    assert_response :forbidden
  end

  def test_new_and_create
    login_with(:write_invoices)
    get '/qbo_invoices/new', params: { customer_id: 9101 }
    assert_response :success
    post '/qbo_invoices', params: { estimate: invoice_params }
    saved = @fake.created.first
    assert_redirected_to "/qbo_invoices/#{saved.id}/edit"
    assert_kind_of Quickbooks::Model::Invoice, saved
  end

  def test_new_from_an_estimate
    login_with(:write_invoices)
    @fake.add(estimate_doc)
    get '/qbo_invoices/new', params: { estimate_id: 598 }
    assert_response :success
    assert_select 'input[name=?][value=?]', 'estimate[linked_estimate_ids][]', '598'

    post '/qbo_invoices', params: { estimate: invoice_params(linked_estimate_ids: ['598']) }
    assert_equal 'Closed', @fake.records['598'].txn_status
  end

  def test_new_from_a_billed_estimate_explains_why
    login_with(:write_invoices)
    @fake.add(estimate_doc(status: 'Closed'))
    get '/qbo_invoices/new', params: { estimate_id: 598 }
    assert_not_equal 500, response.status
    assert_equal I18n.t(:error_estimate_closed_billed, number: '1068', status: 'Closed'), flash[:error]
  end

  def test_save_and_send_needs_send_invoices
    login_with(:write_invoices)
    post '/qbo_invoices', params: { estimate: invoice_params, save_and_send: '1' }
    assert_response :forbidden
    login_with(:send_invoices)
    post '/qbo_invoices', params: { estimate: invoice_params, save_and_send: '1' }
    assert_equal 1, @fake.sent.size
  end

  def test_edit_and_update
    login_with(:write_invoices)
    @fake.add(invoice_doc)
    get '/qbo_invoices/601/edit'
    assert_response :success
    patch '/qbo_invoices/601', params: { estimate: invoice_params(sync_token: '3', lines: line_params(rate: '150')) }
    assert_redirected_to '/qbo_invoices/601/edit'
    assert_equal BigDecimal('300'), @fake.updated.first.line_items.first.amount
  end

  def test_paid_invoice_is_locked
    login_with(:write_invoices)
    @fake.add(invoice_doc(balance: '0'))
    get '/qbo_invoices/601/edit'
    assert_select 'fieldset.qbo-estimate-sheet[disabled]'
    assert_select '#qbo-unlock-invoice', 0
    patch '/qbo_invoices/601', params: { estimate: invoice_params(sync_token: '3'), unlock: '1' }
    assert_response :unprocessable_entity
    assert_empty @fake.updated
  end

  def test_unlock_a_paid_invoice
    login_with(:write_invoices, :edit_paid_invoices)
    @fake.add(invoice_doc(balance: '0'))
    get '/qbo_invoices/601/edit'
    assert_select 'a#qbo-unlock-invoice[href=?]', '/qbo_invoices/601/edit?unlock=1'
    get '/qbo_invoices/601/edit', params: { unlock: 1 }
    assert_select 'fieldset.qbo-estimate-sheet[disabled]', 0
    patch '/qbo_invoices/601', params: { estimate: invoice_params(sync_token: '3', balance: '0'), unlock: '1' }
    assert_redirected_to '/qbo_invoices/601/edit'
  end

  def test_partly_paid_invoice_needs_its_own_permission
    login_with(:write_invoices, :edit_paid_invoices)
    @fake.add(invoice_doc(balance: '100'))
    get '/qbo_invoices/601/edit'
    assert_select '#qbo-unlock-invoice', 0
    login_with(:edit_partially_paid_invoices)
    get '/qbo_invoices/601/edit'
    assert_select '#qbo-unlock-invoice'
  end

  def test_import_options
    login_with(:write_invoices)
    @fake.query_results = { 'FROM Estimate' => [estimate_doc] }
    get '/qbo_invoices/import_options', params: { customer_id: 9101 }
    assert_response :success
    data = JSON.parse(response.body)
    assert_equal ['598'], data['estimates'].map { |e| e['id'] }
    get '/qbo_invoices/import_options', params: { customer_id: 424_242 }
    assert_response :not_found
  end

  def test_send_email
    login_with(:write_invoices, :send_invoices)
    @fake.add(invoice_doc)
    post '/qbo_invoices/601/send_email', params: { email: 'jane@example.com' }
    assert_redirected_to '/qbo_invoices/601/edit'
    assert_equal [%w[601 jane@example.com]], @fake.sent
  end

  def test_drafts
    login_with(:write_invoices)
    post '/qbo_invoices', params: { estimate: invoice_params(sales_person: 'Ricky'), save_draft: '1' }
    draft = QboDraft.last
    assert draft.invoice?
    assert_equal 'Ricky', draft.fields['sales_person']
    assert_redirected_to "/qbo_invoices/new?draft_id=#{draft.id}"
    get "/qbo_invoices/new?draft_id=#{draft.id}"
    assert_response :success
  end
end
