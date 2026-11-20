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

# LaborItems and ManHours
class ManHoursTest < ActiveSupport::TestCase
  def ref(id, name)
    Quickbooks::Model::BaseReference.new(id.to_s, name: name)
  end

  def sales_line(item_id, name, quantity)
    line = Quickbooks::Model::InvoiceLineItem.new
    line.sales_item! do |d|
      d.item_ref = ref(item_id, name)
      d.quantity = BigDecimal(quantity.to_s)
    end
    line
  end

  def invoice(*lines)
    Quickbooks::Model::Invoice.new.tap { |i| i.line_items = lines }
  end

  def test_ids_from_settings
    assert_equal %w[1 2], RedmineQboBilling::LaborItems.ids('labor_item_ids' => [1, '2', '', '1'])
    assert_equal [], RedmineQboBilling::LaborItems.ids({})
  end

  def test_match_by_id_or_name
    labor = RedmineQboBilling::LaborItems
    assert labor.match?(ref(5, 'Anything'), ids: ['5'])
    assert_not labor.match?(ref(6, 'Labor'), ids: ['5'])
    assert labor.match?(ref(6, 'Labor'), ids: [])
    assert labor.match?(ref(6, 'Services:labor'), ids: [])
    assert_not labor.match?(ref(6, 'Laborious part'), ids: [])
    assert_not labor.match?(nil, ids: [])
    assert_not labor.name_matches?('  ', ['Labor'])
    assert labor.name_matches?('Shop Labor', ['shop labor'])
  end

  def test_item_ids_and_names_fall_back_to_matching_names
    Setting.stubs(:plugin_redmine_qbo).returns({})
    Item.stubs(:sellable).returns(stub(pluck: [[11, 'Labor'], [12, 'Brake pads'], [13, 'Shop:Labor']]))
    assert_equal %w[11 13], RedmineQboBilling::LaborItems.item_ids
    assert_equal ['Labor'], RedmineQboBilling::LaborItems.names
  end

  def test_chosen_item_ids_and_names
    Setting.stubs(:plugin_redmine_qbo).returns('labor_item_ids' => ['21'])
    assert_equal ['21'], RedmineQboBilling::LaborItems.item_ids
    Item.stubs(:where).with(id: ['21']).returns(stub(pluck: []))
    assert_equal ['21'], RedmineQboBilling::LaborItems.names
  end

  def test_hours_by_name
    Setting.stubs(:plugin_redmine_qbo).returns({})
    doc = invoice(sales_line(1, 'Labor', 2.5), sales_line(2, 'Brake pads', 4), sales_line(1, 'Labor', '1.25'))
    assert_equal 3.75, RedmineQboBilling::ManHours.hours(doc)
  end

  def test_hours_by_id_include_bundles
    bundle = Quickbooks::Model::InvoiceLineItem.new
    bundle.group_line_detail!
    bundle.group_line_detail.line_items = [sales_line(9, 'Install', 3), sales_line(2, 'Part', 1)]
    doc = invoice(bundle, sales_line(9, 'Install', 1))
    assert_equal 4.0, RedmineQboBilling::ManHours.hours(doc, item_ids: ['9'])
  end

  def test_hours_of_nothing
    assert_equal 0.0, RedmineQboBilling::ManHours.hours(nil)
    assert_equal 0.0, RedmineQboBilling::ManHours.hours(invoice, item_ids: ['9'])
  end
end
