#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Shared setup for the estimate, invoice and payment editor tests: jsmith with chosen billing permissions,
# QuickBooks replaced by QboFakeServiceHelper's fake
module QboEditorTestHelper
  def self.included(base)
    base.include QboFakeServiceHelper
    base.fixtures :projects, :users, :email_addresses, :members, :member_roles, :roles, :issues, :trackers,
                  :projects_trackers, :issue_statuses, :enabled_modules, :enumerations, :workflows
    base.setup do
      @customer = local_customer
      @fake = install_fake_quickbooks
      stub_company
      stub_local_syncs
      Issue.where(estimate_id: [598, 599]).update_all(estimate_id: nil)
      QboDraft.delete_all
      Role.find(1).remove_permission!(*BILLING_PERMISSIONS)
    end
  end

  BILLING_PERMISSIONS = %i[write_estimates send_estimates create_estimate_issues write_invoices send_invoices
                           edit_partially_paid_invoices edit_paid_invoices edit_linked_estimates view_payments
                           receive_payments view_customers].freeze

  def login_with(*permissions)
    permissions.each { |p| Role.find(1).add_permission!(p) }
    reset!
    log_user('jsmith', 'jsmith')
  end

  def estimate_doc(**options)
    qbo_estimate(customer_name: 'Jane Customer', doc_number: '1068', status: 'Pending',
                 lines: [qbo_sales_line(2, 10, 'Labor', 2, 120, description: 'Install lift kit')], **options)
  end

  def invoice_doc(total: '240', balance: '240', **options)
    qbo_invoice(customer_name: 'Jane Customer', doc_number: '1234', total: total, balance: balance,
                lines: [qbo_sales_line(1, 10, 'Labor', 2, 120)], **options)
  end

  def line_params(rate: '120')
    { '0' => { item_id: '10', item_name: 'Labor', quantity: '2', rate: rate, taxable: '0', description: 'Install' } }
  end
end
