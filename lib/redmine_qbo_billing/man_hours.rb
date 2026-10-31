#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.


module RedmineQboBilling
  # The man-hours on a QuickBooks estimate or invoice: the quantities of its labor lines (the plugin setting
  # "Labor products/services", see LaborItems), including lines inside bundles.
  module ManHours
    module_function

    def hours(document, item_ids: LaborItems.ids, codes: nil)
      return 0.0 if document.nil?

      ids = Array(item_ids).map(&:to_s).reject(&:blank?)
      codes ||= LaborItems.codes if ids.empty?
      sum_lines(document.line_items, ids, codes).round(2)
    end

    def sum_lines(lines, ids, codes)
      Array(lines).sum do |line|
        group = line.respond_to?(:group_line_detail) ? line.group_line_detail : nil
        next sum_lines(group.line_items, ids, codes) if group

        detail = sales_detail(line)
        next 0.0 unless detail && LaborItems.match?(detail.item_ref, ids: ids, codes: codes)
        detail.quantity.to_f
      end
    end

    def sales_detail(line)
      if line.respond_to?(:sales_line_item_detail) then line.sales_line_item_detail
      elsif line.respond_to?(:sales_item_line_detail) then line.sales_item_line_detail
      end
    end
  end
end
