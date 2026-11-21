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

class EstimateServiceTest < ActiveSupport::TestCase
  def setup
    Estimate.where(id: 9601).delete_all
    @estimate = Estimate.create!(id: 9601, doc_number: '1068', customer_id: 9101)
  end

  def test_an_estimate_quickbooks_cannot_read_raises_an_ordinary_error
    QboConnectionService.stubs(:with_qbo_service).raises(RuntimeError, 'QBO not connected')
    error = assert_raises(EstimateService::FetchError) { @estimate.details }
    assert_kind_of StandardError, error
    assert_match(/9601/, error.message)
  end

  def test_labor_hours_are_zero_while_quickbooks_is_down
    skip 'redmine_qbo_calendar is not installed' unless defined?(CustomerAppointment)

    QboConnectionService.stubs(:with_qbo_service).raises(RuntimeError, 'QBO not connected')
    assert_equal 0, CustomerAppointment.estimate_labor_hours(@estimate)
  end
end
