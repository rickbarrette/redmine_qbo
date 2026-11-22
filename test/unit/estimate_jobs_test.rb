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

# Grouping an estimate's lines into jobs: each labor line with its parts and notes (RedmineQboBilling::EstimateJobs)
class EstimateJobsTest < ActiveSupport::TestCase
  include QboFakeServiceHelper

  Jobs = RedmineQboBilling::EstimateJobs

  def subtotal
    qbo_subtotal_line
  end

  def labor(id, text, hours = 1)
    qbo_sales_line(id, 10, 'Labor', hours, 190, description: text)
  end

  def part(id, name, text, quantity = 1)
    qbo_sales_line(id, 20 + id, name, quantity, 50, description: text)
  end

  def jobs_for(lines)
    Jobs.new(lines, labor: ->(ref) { ref.name == 'Labor' })
  end

  def parts_of(jobs, line_id)
    jobs.job(line_id).parts.map(&:item_name)
  end

  def test_labor_then_parts_then_subtotal
    jobs = jobs_for([labor(1, 'Replace Ball Joints', 4), part(2, 'TF JK Ball Joints', "Ball joint kit\n3442002"), subtotal,
                     labor(3, 'Replace Front Axle Seals'), part(4, 'JK Front Axle Seal', 'Seal 710863', 2),
                     part(5, '80W-90 Gear Oil', 'Gear oil - quart', 2), subtotal])
    assert_equal ['TF JK Ball Joints'], parts_of(jobs, '1')
    assert_equal ['JK Front Axle Seal', '80W-90 Gear Oil'], parts_of(jobs, '3')
    seal = jobs.job('3').parts.first
    assert_equal ['2', 'Seal 710863'], [seal.quantity, seal.description]
    assert_not jobs.ambiguous?
  end

  def test_parts_before_the_labor_line_belong_to_it
    jobs = jobs_for([part(1, 'Sales', 'Running boards'), labor(2, 'Install side steps', 2)])
    assert_equal ['Sales'], parts_of(jobs, '2')
    assert_not jobs.ambiguous?
  end

  def test_parts_first_jobs_split_by_subtotals
    jobs = jobs_for([part(1, 'Sales', 'Coilovers'), labor(2, 'Install coilovers'), subtotal,
                     part(3, 'Sales', 'Steering kit'), labor(4, 'Install steering')])
    assert_equal ['Sales'], parts_of(jobs, '2')
    assert_equal ['Steering kit'], jobs.job('4').parts.map(&:description)
  end

  def test_a_second_labor_line_takes_the_parts_after_it
    jobs = jobs_for([labor(1, 'Install Ball Joints', 4), part(2, 'TF JL Ball Joints', 'Kit 3452010'),
                     labor(3, 'Standard Alignment'), part(4, 'TPMS Sensor', 'Sensor', 4)])
    assert_equal ['TF JL Ball Joints'], parts_of(jobs, '1')
    assert_equal ['TPMS Sensor'], parts_of(jobs, '3')
    assert_not jobs.ambiguous?
  end

  def test_parts_first_with_no_subtotal_between_jobs_is_ambiguous
    jobs = jobs_for([part(1, 'Sales', 'Coilovers'), labor(2, 'Install coilovers'),
                     part(3, 'Sales', 'Steering kit'), labor(4, 'Install steering')])
    assert jobs.ambiguous?
  end

  def test_notes_at_the_top_are_for_every_job_and_notes_in_a_job_are_its_own
    jobs = jobs_for([qbo_note_line(1, '2015 JKU'), qbo_note_line(2, "Severe play in ball joints\nRecommend ball joints"),
                     labor(3, 'Replace Ball Joints'), part(4, 'Sales', 'Tires'), qbo_note_line(5, 'Take offs, customer provided'),
                     subtotal, labor(6, 'Standard Alignment')])
    assert_equal ['2015 JKU', "Severe play in ball joints\nRecommend ball joints"], jobs.notes
    assert_equal ['Take offs, customer provided'], jobs.job('3').notes
    assert_equal [], jobs.job('6').notes
  end

  def test_parts_with_no_labor_line_are_left_out
    jobs = jobs_for([part(1, 'Sales', 'Wheels', 4), part(2, 'Sales', 'Tires', 4), subtotal, labor(3, 'Replace Steering')])
    assert_equal [], parts_of(jobs, '3')
    assert_nil jobs.job('99')
  end

  def test_whole_number_quantities_drop_the_decimals
    jobs = jobs_for([labor(1, 'Install'), part(2, 'Sales', 'Bolts', 6), part(3, 'Sales', 'Wire', 2.5)])
    assert_equal %w[6 2.5], jobs.job('1').parts.map(&:quantity)
  end
end
