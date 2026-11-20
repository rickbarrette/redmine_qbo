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

class QboSyncStatusTest < ActiveSupport::TestCase
  def setup
    QboSyncStatus.delete_all
  end

  def test_queued_running_progress_finished
    QboSyncStatus.queued('Invoice')
    status = QboSyncStatus.find_by(entity: 'Invoice')
    assert_equal 'queued', status.state
    assert_not status.running?

    QboSyncStatus.running('Invoice')
    QboSyncStatus.progress('Invoice', 25)
    QboSyncStatus.progress(:Invoice, '5')
    status.reload
    assert status.running?
    assert_equal 30, status.processed
    assert status.started_at

    # Asking again while it runs doesn't put it back in the queue
    QboSyncStatus.queued('Invoice')
    assert status.reload.running?

    QboSyncStatus.finished('Invoice')
    assert_not QboSyncStatus.exists?(entity: 'Invoice')
  end

  def test_by_entity_ignores_stale_rows
    QboSyncStatus.queued('Invoice')
    QboSyncStatus.queued('Estimate')
    QboSyncStatus.create!(entity: 'Payment', state: 'running', updated_at: 7.hours.ago)
    assert_equal %w[Estimate Invoice], QboSyncStatus.by_entity.keys.sort
    assert_equal ['Invoice'], QboSyncStatus.by_entity([:Invoice]).keys
  end

  def test_errors_are_logged_not_raised
    QboSyncStatus.stubs(:where).raises(StandardError, 'db gone')
    assert_nothing_raised { QboSyncStatus.progress('Invoice', 1) }
    assert_nothing_raised { QboSyncStatus.finished('Invoice') }
    assert_equal({}, QboSyncStatus.by_entity)
  end
end
