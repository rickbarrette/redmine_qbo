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
  # The labor products/services (plugin setting "Labor products/services", e.g. Labor). They are used to:
  #   * create issues from an estimate's labor lines (and work out its labor hours for appointments)
  #   * offer an invoice's labor lines to be replaced by imported time
  #   * total the man-hours on estimates and invoices for the business report
  #
  # While none are chosen, products/services named "Labor" are used (the full name or any part of a
  # "Category:Item" name, ignoring case).
  module LaborItems
    DEFAULT_CODES = ['Labor'].freeze

    module_function

    # The chosen products/services' QuickBooks ids
    def ids(settings = plugin_settings)
      Array(settings['labor_item_ids']).map(&:to_s).reject(&:blank?).uniq
    end

    # Item names matched while no products/services are chosen
    def codes
      DEFAULT_CODES
    end

    # True when a line's product/service (its ItemRef) is labor
    def match?(item_ref, ids: self.ids, codes: nil)
      return false if item_ref.nil?
      return ids.include?(item_ref.value.to_s) if ids.any?

      name_matches?(item_ref.name, codes || self.codes)
    end

    def name_matches?(item_name, codes)
      name = item_name.to_s.strip.downcase
      return false if name.empty?

      parts = name.split(':').map(&:strip)
      codes.map { |c| c.strip.downcase }.any? { |code| name == code || parts.include?(code) }
    end

    # The labor products/services as ids: the chosen ones, else the local items whose names match the codes
    # (for the settings page and the invoice's Replace these lines list)
    def item_ids
      chosen = ids
      return chosen if chosen.any?

      list = codes
      Item.where(active: true).pluck(:id, :name).select { |_, name| name_matches?(name, list) }.map { |id, _| id.to_s }
    rescue StandardError
      []
    end

    # Names to show, e.g. when an estimate has no labor lines
    def names
      chosen = ids
      return codes if chosen.empty?

      Item.where(id: chosen).pluck(:name).presence || chosen
    rescue StandardError
      chosen
    end

    def plugin_settings
      Setting.plugin_redmine_qbo || {}
    rescue StandardError
      {}
    end
  end
end
