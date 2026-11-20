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

# WebhookProcessJob, QboSyncDispatcher and QboSyncJob
class QboSyncJobsTest < ActiveSupport::TestCase
  def setup
    QboSyncStatus.delete_all
    Qbo.stubs(:update_time_stamp)
  end

  def notification(*entities)
    { eventNotifications: [{ realmId: '1', dataChangeEvent: { entities: entities } }] }.to_json
  end

  # Items and accounts come from the plugin's own hook (QboHookListener); anything else is ignored
  def test_webhook_syncs_allowed_entities
    Invoice.expects(:sync_by_id).with(601)
    Customer.expects(:sync_by_id).with(9101)
    Item.expects(:sync_by_id).with(5)
    Account.expects(:sync_by_id).with(84)
    Kernel.expects(:sync_by_id).never
    WebhookProcessJob.perform_now(notification({ name: 'Invoice', id: '601', operation: 'Update' },
                                               { name: 'Customer', id: '9101', operation: 'Create' },
                                               { name: 'Item', id: '5', operation: 'Update' },
                                               { name: 'Account', id: '84', operation: 'Update' },
                                               { name: 'Kernel', id: '1', operation: 'Update' },
                                               { name: 'Vendor', id: '2', operation: 'Update' }))
  end

  def test_webhook_deletes
    Estimate.expects(:delete).with(598)
    Payment.expects(:delete).with('801')
    WebhookProcessJob.perform_now(notification({ name: 'Estimate', id: '598', operation: 'Delete' },
                                               { name: 'Payment', id: '802', operation: 'Merge', deletedId: '801' }))
  end

  def test_plugins_add_webhook_entities
    Redmine::Hook.stubs(:call_hook).with(:qbo_additional_entities).returns([['Vehicle'], nil])
    vehicle = Class.new { def self.sync_by_id(_id); end }
    Object.const_set(:Vehicle, vehicle) unless defined?(::Vehicle)
    ::Vehicle.expects(:sync_by_id).with(5)
    WebhookProcessJob.perform_now(notification({ name: 'Vehicle', id: '5', operation: 'Update' }))
  ensure
    Object.send(:remove_const, :Vehicle) if defined?(::Vehicle) && ::Vehicle == vehicle
  end

  def test_plugin_hook_adds_items_and_accounts
    listener = RedmineQboBilling::Hooks::QboHookListener.instance
    assert_equal %w[Item Account], listener.qbo_additional_entities
    assert_equal [Account, Item], listener.qbo_full_sync
  end

  def test_one_bad_entity_does_not_stop_the_rest
    Invoice.stubs(:sync_by_id).raises(StandardError, 'boom')
    Customer.expects(:sync_by_id).with(9101)
    WebhookProcessJob.perform_now(notification({ name: 'Invoice', id: '601' }, { name: 'Customer', id: '9101' }))
  end

  def test_webhook_updates_the_time_stamp
    Qbo.expects(:update_time_stamp)
    WebhookProcessJob.perform_now('{}')
  end

  def test_dispatcher_queues_every_entity_payments_before_invoices
    queued = []
    QboSyncJob.stubs(:perform_later).with { |args| queued << [args[:entity].to_s, args[:full_sync]] }
    Redmine::Hook.stubs(:call_hook).with(:qbo_full_sync).returns([[Item], nil])
    QboSyncDispatcher.sync!(full_sync: true)
    assert_equal %w[Customer Estimate Payment Invoice Employee Item], queued.map(&:first)
    assert queued.all?(&:last)
    assert_equal 6, QboSyncStatus.where(state: 'queued').count
  end

  def test_sync_job_by_id_doc_number_or_all
    CustomerSyncService.any_instance.expects(:sync_by_id).with(9101)
    QboSyncJob.perform_now(entity: 'Customer', id: 9101)

    EstimateSyncService.any_instance.expects(:sync_by_doc_number).with('1068')
    QboSyncJob.perform_now(entity: 'Estimate', doc_number: '1068')

    InvoiceSyncService.any_instance.expects(:sync).with(full_sync: true)
    QboSyncStatus.queued('Invoice')
    QboSyncJob.perform_now(entity: 'Invoice', full_sync: true)
    assert_not QboSyncStatus.exists?(entity: 'Invoice')
  end

  def test_sync_status_is_cleared_when_the_sync_fails
    InvoiceSyncService.any_instance.stubs(:sync).raises(StandardError, 'QuickBooks down')
    job = QboSyncJob.new(entity: 'Invoice')
    assert_raises(StandardError) { job.perform(entity: 'Invoice') }
    assert_not QboSyncStatus.exists?(entity: 'Invoice')
  end

  def test_sync_job_needs_an_entity
    assert_raises(RuntimeError) { QboSyncJob.new.perform }
  end
end
