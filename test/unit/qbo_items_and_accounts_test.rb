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

# Item, Account and what every QuickBooks-backed model shares (QboBaseModel)
class QboItemsAndAccountsTest < ActiveSupport::TestCase
  def setup
    Item.where(id: [9701, 9702, 9703, 9704]).delete_all
    Account.where(id: [9801, 9802]).delete_all
  end

  def item(id, attrs = {})
    record = Item.new({ id: id, name: "Item #{id}", description: '', unit_price: 10, active: true, type: 'Service' }.merge(attrs))
    record.skip_qbo_push = true
    record.save!
    record
  end

  def account(id, attrs = {})
    Account.create!({ id: id, name: "Account #{id}" }.merge(attrs))
  end

  def test_item_setters_write_through_to_quickbooks
    income = account(9801, name: 'Sales')
    record = Item.new(id: 9701, name: 'Labor', description: 'Shop labor', sku: 'LAB', unit_price: 120, type: 'Service',
                      account_id: income.id)
    assert_equal 'Labor', record.details.name
    assert_equal 'Shop labor', record.details.description
    assert_equal 'LAB', record.details.sku
    assert_equal BigDecimal('120'), record.details.unit_price
    assert_equal 'Service', record.details.type
    assert_equal '9801', record.details.income_account_ref.value.to_s
    assert record.taxable
  end

  def test_unknown_account_leaves_the_quickbooks_ref_alone
    record = Item.new(id: 9701, name: 'Labor', account_id: 12_345)
    assert_nil record.details.income_account_ref
    assert_equal 12_345, record.account_id
  end

  def test_item_validation
    assert_not Item.new(id: 9701, name: '').tap { |i| i.skip_qbo_push = true }.valid?
    assert_not Item.new(id: 9701, name: 'Part', unit_price: -1).tap { |i| i.skip_qbo_push = true }.valid?
  end

  def test_sellable
    item(9701)
    item(9702, type: 'Category')
    item(9703, active: false)
    item(9704, type: nil)
    assert_equal [9701, 9704], Item.sellable.where(id: [9701, 9702, 9703, 9704]).order(:id).pluck(:id)
  end

  def test_destroying_an_item_makes_it_inactive_in_quickbooks
    record = item(9701)
    record.expects(:push_to_qbo).once
    record.destroy
    assert_equal false, record.details.active?
  end

  def test_one_default_account
    first = account(9801, default: true)
    second = account(9802, default: true)
    assert_not first.reload.default
    assert_equal second, Account.get_default
    ref = second.ref
    assert_equal 9802, ref.value
    assert_equal 'Account 9802', ref.name
    assert_equal 'Account 9802', second.to_s
  end

  def test_push_toggle
    assert Item.qbo_push_enabled
    assert_not Estimate.qbo_push_enabled
    record = Item.new(id: 9701, name: 'Part')
    assert record.push_to_qbo?
    record.skip_qbo_push = true
    assert_not record.push_to_qbo?
    assert_not Estimate.new.push_to_qbo?
  end

  def test_method_missing_reaches_the_quickbooks_entity
    record = Item.new(id: 9701, name: 'Part')
    assert record.respond_to?(:purchase_desc)
    record.purchase_desc = 'Bought in bulk'
    assert_equal 'Bought in bulk', record.purchase_desc
    assert_raises(NoMethodError) { record.not_a_quickbooks_field }
  end

  def test_sync_queues_jobs
    QboSyncStatus.delete_all
    QboSyncJob.expects(:perform_later).with(entity: 'Item', full_sync: true)
    Item.sync
    assert_equal 'queued', QboSyncStatus.find_by(entity: 'Item').state
    QboSyncJob.expects(:perform_later).with(entity: 'Item', id: 5)
    Item.sync_by_id(5)
    QboSyncJob.expects(:perform_later).with(entity: 'Estimate', doc_number: '1068')
    Estimate.sync_by_doc_number('1068')
  end

  def test_last_sync
    Employee.delete_all
    assert_equal I18n.t(:label_qbo_never_synced), Employee.last_sync
  end

  def test_estimate_line_issue_link
    QboEstimateLineIssue.delete_all
    link = QboEstimateLineIssue.create!(estimate_id: 1, line_id: '3', issue_id: 1)
    assert link.created_on
    assert_not QboEstimateLineIssue.new(estimate_id: 1, line_id: '3', issue_id: 2).valid?
    assert_not QboEstimateLineIssue.new(line_id: '4').valid?
  end
end
