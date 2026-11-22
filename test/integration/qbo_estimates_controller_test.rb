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

class QboEstimatesControllerTest < Redmine::IntegrationTest
  include QboEditorTestHelper

  def estimate_params(extra = {})
    { customer_id: '9101', txn_date: '2026-11-20', email: 'jane@example.com', lines: line_params }.merge(extra)
  end

  def test_editor_needs_write_estimates
    login_with(:view_customers)
    get '/qbo_estimates/new'
    assert_response :forbidden
    post '/qbo_estimates', params: { estimate: estimate_params }
    assert_response :forbidden
    assert_empty @fake.created
  end

  def test_new_estimate
    login_with(:write_estimates)
    get '/qbo_estimates/new', params: { customer_id: 9101 }
    assert_response :success
    assert_select 'input[name=?][value=?]', 'estimate[customer_id]', '9101'
  end

  def test_create
    login_with(:write_estimates)
    post '/qbo_estimates', params: { estimate: estimate_params }
    saved = @fake.created.first
    assert saved
    assert_redirected_to "/qbo_estimates/#{saved.id}/edit"
    assert_equal BigDecimal('240'), saved.line_items.first.amount
  end

  def test_invalid_form_is_shown_again
    login_with(:write_estimates)
    post '/qbo_estimates', params: { estimate: estimate_params(customer_id: '', lines: {}) }
    assert_response :unprocessable_entity
    assert_select '#errorExplanation', text: /#{Regexp.escape(I18n.t(:error_estimate_needs_customer))}/
    assert_empty @fake.created
  end

  def test_save_and_send_needs_send_estimates
    login_with(:write_estimates)
    post '/qbo_estimates', params: { estimate: estimate_params, save_and_send: '1' }
    assert_response :forbidden

    login_with(:send_estimates)
    post '/qbo_estimates', params: { estimate: estimate_params, save_and_send: '1' }
    assert_equal [[@fake.created.first.id, 'jane@example.com']], @fake.sent
  end

  def test_quickbooks_error_is_shown
    login_with(:write_estimates)
    @fake.define_singleton_method(:create) { |_doc| raise Quickbooks::IntuitRequestException, 'Business Validation Error' }
    post '/qbo_estimates', params: { estimate: estimate_params }
    assert_response :unprocessable_entity
    assert_select '#errorExplanation', text: /Business Validation Error/
  end

  def test_edit_and_update
    login_with(:write_estimates)
    @fake.add(estimate_doc)
    get '/qbo_estimates/598/edit'
    assert_response :success
    assert_select 'fieldset.qbo-estimate-sheet[disabled]', 0

    patch '/qbo_estimates/598', params: { estimate: estimate_params(sync_token: '3', lines: line_params(rate: '150')) }
    assert_redirected_to '/qbo_estimates/598/edit'
    assert_equal BigDecimal('300'), @fake.updated.first.line_items.first.amount
  end

  def test_stale_update_is_a_conflict
    login_with(:write_estimates)
    @fake.add(estimate_doc)
    patch '/qbo_estimates/598', params: { estimate: estimate_params(sync_token: '1') }
    assert_response :unprocessable_entity
    assert_select '#errorExplanation', text: /#{Regexp.escape(I18n.t(:error_estimate_changed_in_quickbooks))}/
  end

  def test_missing_estimate_redirects
    login_with(:write_estimates)
    get '/qbo_estimates/999/edit'
    assert_response :redirect
    assert_equal I18n.t(:notice_estimate_not_found), flash[:error]
  end

  # ---- estimates linked to an issue ----

  def test_linked_estimate_is_read_only_without_the_permission
    login_with(:write_estimates)
    @fake.add(estimate_doc)
    Issue.find(1).update_column(:estimate_id, 598)
    get '/qbo_estimates/598/edit'
    assert_select 'fieldset.qbo-estimate-sheet[disabled]'
    assert_select '#qbo-unlock-estimate', 0
    # Asking to unlock without the permission changes nothing
    get '/qbo_estimates/598/edit', params: { unlock: 1 }
    assert_select 'fieldset.qbo-estimate-sheet[disabled]'
    patch '/qbo_estimates/598', params: { estimate: estimate_params(sync_token: '3'), unlock: '1' }
    assert_response :unprocessable_entity
    assert_empty @fake.updated
  end

  def test_unlock_a_linked_estimate
    login_with(:write_estimates, :edit_linked_estimates)
    @fake.add(estimate_doc)
    Issue.find(1).update_column(:estimate_id, 598)
    get '/qbo_estimates/598/edit'
    assert_select 'a#qbo-unlock-estimate[href=?][data-confirm=?]', '/qbo_estimates/598/edit?unlock=1',
                  I18n.t(:text_unlock_estimate_confirmation)

    get '/qbo_estimates/598/edit', params: { unlock: 1 }
    assert_select 'fieldset.qbo-estimate-sheet[disabled]', 0
    assert_select 'input[type=hidden][name=unlock][value="1"]'
    assert_select '.qbo-estimate-notice', text: /#{Regexp.escape(I18n.t(:text_estimate_unlocked))}/

    patch '/qbo_estimates/598', params: { estimate: estimate_params(sync_token: '3', lines: line_params(rate: '150')), unlock: '1' }
    assert_redirected_to '/qbo_estimates/598/edit'
    assert_equal BigDecimal('300'), @fake.updated.first.line_items.first.amount
    assert_equal 598, Issue.find(1).estimate_id
  end

  def test_billed_estimate_cannot_be_unlocked
    login_with(:write_estimates, :edit_linked_estimates)
    @fake.add(estimate_doc(status: 'Closed'))
    Issue.find(1).update_column(:estimate_id, 598)
    get '/qbo_estimates/598/edit', params: { unlock: 1 }
    assert_select 'fieldset.qbo-estimate-sheet[disabled]'
    patch '/qbo_estimates/598', params: { estimate: estimate_params(sync_token: '3'), unlock: '1' }
    assert_response :unprocessable_entity
    assert_empty @fake.updated
  end

  # ---- duplicates, drafts, emails ----

  def test_duplicate
    login_with(:write_estimates)
    @fake.add(estimate_doc)
    get '/qbo_estimates/new', params: { duplicate: 598 }
    assert_response :success
    assert_select '.flash.notice', text: /1068/
  end

  def test_drafts
    login_with(:write_estimates)
    post '/qbo_estimates', params: { estimate: estimate_params(customer_id: '9101', lines: line_params), save_draft: '1' }
    draft = QboDraft.last
    assert_redirected_to "/qbo_estimates/new?draft_id=#{draft.id}"
    assert_equal [9101, 2], [draft.customer_id, draft.user_id]
    get "/qbo_estimates/new?draft_id=#{draft.id}"
    assert_response :success

    # Saving to QuickBooks deletes the draft
    post '/qbo_estimates', params: { estimate: estimate_params, draft_id: draft.id }
    assert_not QboDraft.exists?(draft.id)

    get '/qbo_estimates/new', params: { draft_id: draft.id }
    assert_redirected_to '/qbo_drafts'
  end

  def test_send_email
    login_with(:write_estimates)
    @fake.add(estimate_doc)
    post '/qbo_estimates/598/send_email', params: { email: 'jane@example.com' }
    assert_response :forbidden
    login_with(:send_estimates)
    post '/qbo_estimates/598/send_email', params: { email: 'jane@example.com' }
    assert_redirected_to '/qbo_estimates/598/edit'
    assert_equal [%w[598 jane@example.com]], @fake.sent
  end

  # ---- editor lookups ----

  def test_customer_info
    login_with(:write_estimates)
    get '/qbo_estimates/customer_info', params: { customer_id: 9101 }
    assert_equal 'Jane Customer', JSON.parse(response.body)['name']
    get '/qbo_estimates/customer_info', params: { customer_id: 424_242 }
    assert_response :not_found
    get '/qbo_estimates/customer_info', params: { customer_id: 9101, document: 'invoice' }
    assert JSON.parse(response.body).key?('open_issues_html')
  end

  def test_items_search
    Item.where(id: [9701, 9702]).delete_all
    [[9701, 'Labor', true], [9702, 'Lab coat', false]].each do |id, name, active|
      Item.new(id: id, name: name, description: '', unit_price: 120, active: active, type: 'Service')
          .tap { |i| i.skip_qbo_push = true }.save!
    end
    login_with(:write_invoices)
    get '/qbo_estimates/items', params: { q: 'lab' }
    assert_equal [9701], JSON.parse(response.body).map { |i| i['id'] }
  end

  def test_refresh_company_is_admin_only
    login_with(:write_estimates)
    post '/qbo_estimates/refresh_company'
    assert_response :forbidden
    reset!
    log_user('admin', 'admin')
    RedmineQboBilling::Company.expects(:refresh!)
    post '/qbo_estimates/refresh_company'
    assert_response :redirect
  end

  # ---- issues from an estimate ----

  def test_issues_from_an_estimate
    Estimate.where(id: 598).delete_all
    Estimate.create!(id: 598, doc_number: '1068', customer_id: 9101)
    Estimate.any_instance.stubs(:line_items).returns([qbo_sales_line(2, 10, 'Labor', 2, 120, description: 'Install lift kit')])
    Setting.stubs(:plugin_redmine_qbo).returns('issue_default_project_id' => '1')
    @fake.add(estimate_doc)

    login_with(:write_estimates)
    get '/qbo_estimates/598/issues_preview'
    assert_response :forbidden

    login_with(:create_estimate_issues, :add_issues)
    get '/qbo_estimates/598/issues_preview'
    assert_response :success

    post '/qbo_estimates/598/create_issues', params: { project_id: 1, lines: { '2' => { selected: '1', tracker_id: '1' } } }
    assert_redirected_to '/qbo_estimates/598/edit'
    issue = Issue.where(estimate_id: 598).last
    assert_equal 'Install Lift Kit', issue.subject
    # The work is going ahead: the estimate is accepted
    assert_equal 'Accepted', @fake.updated.last.txn_status
  end

  def test_create_issues_with_nothing_selected
    Estimate.where(id: 598).delete_all
    Estimate.create!(id: 598, doc_number: '1068', customer_id: 9101)
    Estimate.any_instance.stubs(:line_items).returns([qbo_sales_line(2, 10, 'Labor', 2, 120, description: 'Install')])
    login_with(:create_estimate_issues, :add_issues)
    post '/qbo_estimates/598/create_issues', params: { project_id: 1, lines: {} }
    assert_response :unprocessable_entity
  end

  def test_issues_preview_suggests_templates_and_lists_parts
    Estimate.where(id: 598).delete_all
    Estimate.create!(id: 598, doc_number: '1068', customer_id: 9101)
    Estimate.any_instance.stubs(:line_items).returns([
      qbo_sales_line(2, 31, 'Sales', 1, 315, description: 'Running boards'),
      qbo_sales_line(3, 10, 'Labor', 2, 190, description: 'Install side steps'),
      qbo_sales_line(4, 32, 'Sales', 1, 99, description: 'Light bar'),
      qbo_sales_line(5, 10, 'Labor', 1, 190, description: 'Install light bar')
    ])
    Setting.stubs(:plugin_redmine_qbo).returns('issue_default_project_id' => '1', 'issue_default_tracker_id' => '1')
    option = RedmineQboBilling::IssueTemplateSupport::Option
    RedmineQboBilling::IssueTemplateSupport.stubs(:enabled_for?).returns(true)
    RedmineQboBilling::IssueTemplateSupport.stubs(:templates_for).returns([
      option.new(key: 'project:1', title: 'Default', tracker_id: 1, is_default: true, group: 'project', match_phrases: []),
      option.new(key: 'project:2', title: 'Side Steps', tracker_id: 2, is_default: false, group: 'project',
                 match_phrases: ['side steps', 'running boards'])
    ])

    login_with(:create_estimate_issues, :add_issues)
    get '/qbo_estimates/598/issues_preview'
    assert_response :success
    # Install side steps: matched template and its tracker
    assert_select 'select[name="lines[3][tracker_id]"] option[selected][value="2"]'
    assert_select 'select[name="lines[3][template]"] option[selected][value="project:2"]'
    # Install light bar: no match, the tracker's default template
    assert_select 'select[name="lines[5][template]"] option[selected][value="project:1"]'
    assert_select '.estimate-line-parts', text: /1 × Sales/
    # Parts first, then two labor lines with no subtotal between them
    assert_select '.estimate-parts-ambiguous'
  end
end
