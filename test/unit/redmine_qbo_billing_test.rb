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

# RedmineQboBilling's permission helpers and plugin hooks for the editor's custom fields
class RedmineQboBillingTest < ActiveSupport::TestCase
  Billing = RedmineQboBilling

  def user(*permissions)
    user = User.new
    user.stubs(:allowed_to?).returns(false)
    permissions.each { |p| user.stubs(:allowed_to?).with(p, nil, global: true).returns(true) }
    user
  end

  def test_simple_permissions
    { writer?: :write_estimates, sender?: :send_estimates, payment_receiver?: :receive_payments,
      refunder?: :issue_refunds, invoice_writer?: :write_invoices, invoice_sender?: :send_invoices }.each do |helper, permission|
      assert Billing.public_send(helper, user(permission)), helper
      assert_not Billing.public_send(helper, user), helper
    end
  end

  def test_payment_viewer
    assert Billing.payment_viewer?(user(:view_payments))
    assert Billing.payment_viewer?(user(:receive_payments))
    assert_not Billing.payment_viewer?(user)
  end

  def test_paid_invoice_editor
    assert Billing.paid_invoice_editor?(true, user(:write_invoices, :edit_paid_invoices))
    assert_not Billing.paid_invoice_editor?(false, user(:write_invoices, :edit_paid_invoices))
    assert Billing.paid_invoice_editor?(false, user(:write_invoices, :edit_partially_paid_invoices))
    assert_not Billing.paid_invoice_editor?(true, user(:write_invoices, :edit_partially_paid_invoices))
    assert_not Billing.paid_invoice_editor?(true, user(:edit_paid_invoices))
  end

  def test_field_options_merge_and_dedupe
    field = Struct.new(:id).new(2)
    Redmine::Hook.stubs(:call_hook).with(:qbo_billing_field_options, anything).returns([
      { field => [{ value: 'vin1', label: 'Jeep' }, { 'value' => ' ' }] },
      { '2' => [{ value: 'VIN1' }, { value: 'VIN2' }] },
      'not a hash'
    ])
    assert_equal({ '2' => [{ value: 'vin1', label: 'Jeep' }, { value: 'VIN2', label: 'VIN2' }] },
                 Billing.field_options(Customer.new))
    assert_equal({}, Billing.field_options(nil))
  end

  def test_field_options_survive_a_failing_plugin
    Redmine::Hook.stubs(:call_hook).raises(StandardError)
    assert_equal({}, Billing.field_options(Customer.new))
    assert_equal({}, Billing.field_defaults(Customer.new))
  end

  def test_field_defaults_first_value_wins
    Redmine::Hook.stubs(:call_hook).with(:qbo_billing_field_defaults, has_entries(issues: [])).returns([
      { 2 => '', 3 => 'first' }, { '2' => 'VIN', '3' => 'second' }, nil
    ])
    assert_equal({ '3' => 'first', '2' => 'VIN' }, Billing.field_defaults(Customer.new))
    assert_equal({}, Billing.field_defaults(nil))
  end
end
