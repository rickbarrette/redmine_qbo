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

class CustomerSearchServiceTest < ActiveSupport::TestCase
  Search = CustomerSearchService

  ROWS = [
    [1, 'William Smith', '4015550101', nil],
    [2, 'Robert Jones', nil, '4015550199'],
    [3, 'Kathy McDonald', '5085551234', nil],
    [4, "Sean O'Brien LLC", nil, nil],
    [5, 'José Alvarez', nil, nil],
    [6, 'Jon Smyth', nil, nil]
  ].freeze

  def rank(**query)
    Search.rank(Search.prepare(ROWS), **query).map(&:first)
  end

  def test_tokens
    assert_equal %w[obrien smith jose], Search.tokens("O'Brien-Smith, José")
    assert_equal %w[sean obrien], Search.tokens("Sean O'Brien LLC")
    assert_equal %w[the company], Search.tokens('The Company')
  end

  def test_nicknames_sound_alikes_typos_and_order
    assert_equal 1, rank(name: 'Bill Smith').first
    assert_equal 2, rank(name: 'Bob Jones').first
    assert_equal 1, rank(name: 'Smith, William').first
    assert_equal 1, rank(name: 'Willaim Smtih').first
    assert_includes rank(name: 'John Smith'), 6
    assert_equal 3, rank(name: 'Cathy Mc Donald').first
    assert_equal 5, rank(name: 'jose alvarez').first
  end

  def test_partial_names_while_typing
    assert_equal 1, rank(name: 'will smi').first
    assert_equal 1, rank(name: 'bil smith').first
  end

  def test_unrelated_names_do_not_match
    assert_empty rank(name: 'Bill Jones') & [1]
    assert_empty rank(name: 'Zebulon')
    assert_empty rank(name: '')
  end

  def test_phone_numbers
    assert_equal [2], rank(phone: '0199')
    assert_equal [1], rank(name: '(401) 555-0101')
    assert_equal [], rank(phone: '12')
    assert_equal 1.0, Search.phone_score('5550101', ['4015550101'])
    assert_equal 0.9, Search.phone_score('5550', ['4015550101'])
  end

  def test_limit
    assert_equal 1, Search.rank(Search.prepare(ROWS), phone: '401555', limit: 1).size
  end

  def test_nicknames_need_a_shared_longer_name
    assert Search.nicknames?('bill', 'will')
    assert_not Search.nicknames?('william', 'robert')
    assert Search.nicknames?('liam', 'william')
  end

  def test_call_returns_customers_best_first
    Customer.where(id: [9101, 9102]).delete_all
    [[9101, 'William Smith'], [9102, 'Bill Smithers']].each do |id, name|
      Customer.new(id: id, name: name).tap { |c| c.skip_qbo_push = true }.save!
    end
    assert_equal 9101, Search.call(name: 'William Smith').first.id
    assert_empty Search.call(name: 'zzzz')
  end
end
