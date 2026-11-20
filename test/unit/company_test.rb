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

class CompanyTest < ActiveSupport::TestCase
  include QboFakeServiceHelper
  Company = RedmineQboBilling::Company

  def name_value(name, string: nil, boolean: nil)
    Struct.new(:name, :string_value, :boolean_value).new(name, string, boolean)
  end

  def settings(fields, extra = {})
    Company.stubs(:settings).returns({ custom_fields: fields }.merge(extra))
  end

  def test_parse_custom_fields
    entries = [name_value('SalesFormsPrefs.UseSalesCustom1', boolean: 'true'),
               name_value('SalesFormsPrefs.SalesCustomName1', string: ' Sales Rep '),
               name_value('SalesFormsPrefs.UseSalesCustom2', boolean: 'false'),
               name_value('SalesFormsPrefs.SalesCustomName2', string: 'Old'),
               name_value('SalesFormsPrefs.SalesCustomName3', string: 'VIN'),
               name_value('SalesFormsPrefs.SalesCustomName4', string: '')]
    assert_equal [{ id: 1, name: 'Sales Rep' }, { id: 3, name: 'VIN' }], Company.parse_custom_fields(entries)
  end

  def test_merge_fields_prefers_newer_custom_fields
    legacy = [{ id: 1, name: 'Sales Rep old' }]
    assert_equal [{ id: 5_000_001, name: 'Sales Person' }],
                 Company.merge_fields(legacy, [{ id: 1, name: 'x' }, { id: 5_000_001, name: 'Sales Person' }])
    assert_equal [{ id: 1, name: 'Sales Rep old' }, { id: 2, name: 'VIN' }],
                 Company.merge_fields(legacy, [{ id: 1, name: 'Sales' }, { id: 2, name: 'VIN' }])
  end

  def test_fields_hidden_in_settings_are_left_out
    settings([{ id: 1, name: 'Sales Rep' }, { id: 2, name: 'VIN' }, { id: 3, name: 'Mileage' }])
    Setting.stubs(:plugin_redmine_qbo).returns('hidden_custom_field_ids' => ['3', ''])
    assert_equal [1, 2], Company.custom_fields.map(&:id)
    assert_equal [1, 2, 3], Company.all_custom_fields.map(&:id)
    assert_equal 1, Company.sales_person_field.id
    assert_equal [2], Company.editable_custom_fields.map(&:id)
    assert_equal 2, Company.custom_field_matching(/\bvin\b/i).id
    assert_nil Company.custom_field_matching(/mileage/i)
  end

  def test_flags_and_messages
    settings([], custom_txn_numbers: true, allow_discount: false, estimate_message: 'Thanks', invoice_message: nil)
    assert Company.custom_txn_numbers?
    assert_not Company.discounts_allowed?
    assert_equal 'Thanks', Company.estimate_message
    assert_equal '', Company.invoice_message
    settings([])
    assert Company.discounts_allowed?
    assert_not Company.custom_txn_numbers?
  end

  def test_fetch_settings_from_preferences_and_recent_estimates
    fake = install_fake_quickbooks
    prefs = Struct.new(:sales_forms).new(
      Struct.new(:custom_fields, :custom_txn_numbers?, :allow_discount?, :estimate_message, :default_customer_message)
            .new([name_value('SalesFormsPrefs.SalesCustomName1', string: 'Sales Rep')], 'true', 'false', 'Thanks', 'Pay up')
    )
    fake.query_results = { 'Preferences' => [prefs],
                           'FROM Estimate' => [qbo_estimate(custom_fields: [qbo_custom_field(2, 'VIN', 'x')])] }
    result = Company.fetch_settings
    assert_equal [{ id: 1, name: 'Sales Rep' }, { id: 2, name: 'VIN' }], result[:custom_fields]
    assert_equal [true, false, 'Thanks', 'Pay up'], result.values_at(:custom_txn_numbers, :allow_discount, :estimate_message, :invoice_message)
  end

  def test_settings_are_empty_when_quickbooks_is_unreachable
    QboConnectionService.stubs(:with_qbo_service).raises(StandardError, 'QBO not connected')
    assert_nil Company.fetch_settings
    assert_equal({}, Company.settings)
    assert_equal({}, Company.refresh!)
  end
end
