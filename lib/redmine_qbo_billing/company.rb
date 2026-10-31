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
  # What the QuickBooks company is set up with, read from its Preferences so nothing has to be configured
  # in Redmine: the sales form custom fields, whether estimate numbers are typed by hand, and the default
  # messages. Every enabled text custom field gets a box on the estimate/invoice editor; the sales person
  # (found by name) is filled in automatically. Other plugins find the fields they fill by name
  # (custom_field_matching), e.g. redmine_qbo_vehicles' VIN.
  #
  # QuickBooks only shares its first three text custom fields with apps (dropdown fields aren't
  # available), so a "Sales Person" dropdown has to be changed to a text field to be filled in here.
  module Company
    CACHE_KEY = 'redmine_qbo_billing:company'
    CACHE_TIME = 1.hour
    # While no custom fields are found, look again sooner (e.g. right after adding one in QuickBooks)
    MISSING_FIELD_CACHE_TIME = 5.minutes
    # Recent estimates also show which custom fields exist, for companies whose preferences don't list them
    RECENT_ESTIMATES = 20

    # The sales person field is found loosely, e.g. "Sales Person", "Salesperson", "Sales Rep"
    SALES_PERSON_NAME = /sales|\brep\b/i

    Field = Struct.new(:id, :name)

    module_function

    # All enabled sales form custom fields, in QuickBooks' order
    def custom_fields
      Array(settings[:custom_fields]).map { |f| Field.new(f[:id], f[:name]) }
    end

    # The first enabled custom field whose name matches, e.g. a plugin's VIN field (/\bvin\b/i), or nil
    def custom_field_matching(pattern)
      custom_fields.detect { |f| f.name.to_s =~ pattern }
    end

    # The custom fields edited on the estimate/invoice editor: all of them except the sales person, which is
    # filled in automatically
    def editable_custom_fields
      sales = sales_person_field
      custom_fields.reject { |f| sales && f.id.to_i == sales.id.to_i }
    end

    def sales_person_field
      custom_fields.detect { |f| f.name.to_s =~ SALES_PERSON_NAME }
    end

    # When on, QuickBooks leaves estimate numbers to the user; when off it numbers them itself
    def custom_txn_numbers?
      settings[:custom_txn_numbers] == true
    end

    # The "default message shown on estimates" from QuickBooks' sales settings
    def estimate_message
      settings[:estimate_message].to_s
    end

    # The "default message shown on invoices" (and other sales forms)
    def invoice_message
      settings[:invoice_message].to_s
    end

    # Forgets the cached preferences, e.g. after a custom field was renamed in QuickBooks
    def refresh!
      Rails.cache.delete(CACHE_KEY)
      settings
    end

    # Cached for an hour (five minutes while a field is missing). A failed lookup isn't cached.
    def settings
      cached = Rails.cache.read(CACHE_KEY)
      return cached if cached

      fresh = fetch_settings
      return {} unless fresh

      complete = Array(fresh[:custom_fields]).any?
      Rails.cache.write(CACHE_KEY, fresh, expires_in: complete ? CACHE_TIME : MISSING_FIELD_CACHE_TIME)
      fresh
    end

    def fetch_settings
      QboConnectionService.with_qbo_service(entity: 'Preferences') do |service|
        prefs = service.query.entries.first
        return nil unless prefs

        forms = prefs.sales_forms
        {
          custom_fields: merge_fields(parse_custom_fields(forms&.custom_fields), custom_fields_from_estimates),
          custom_txn_numbers: forms&.custom_txn_numbers? == 'true' || forms&.custom_txn_numbers? == true,
          estimate_message: forms&.estimate_message.to_s,
          invoice_message: forms&.default_customer_message.to_s
        }
      end
    rescue StandardError => e
      Rails.logger.warn "[RedmineQboBilling] Could not read QuickBooks preferences: #{e.message}"
      nil
    end

    # Fields named in the preferences come first; fields only seen on estimates are added after them.
    # QuickBooks' newer custom fields (e.g. on Advanced and sandbox companies) may not be in the preferences.
    def merge_fields(from_preferences, from_estimates)
      ids = from_preferences.map { |f| f[:id] }
      from_preferences + from_estimates.reject { |f| ids.include?(f[:id]) }
    end

    # The text custom fields on the most recently changed estimates
    def custom_fields_from_estimates
      estimates = QboEstimateService.with_service do |service|
        service.query('SELECT * FROM Estimate ORDERBY MetaData.LastUpdatedTime DESC', per_page: RECENT_ESTIMATES).entries
      end

      Array(estimates).flat_map { |e| Array(e.custom_fields) }
                      .select { |f| f.id.to_i > 0 && f.name.present? && (f.type.blank? || f.type.to_s == 'StringType') }
                      .map { |f| { id: f.id.to_i, name: f.name.to_s.strip } }
                      .uniq { |f| f[:id] }
                      .sort_by { |f| f[:id] }
    rescue StandardError => e
      Rails.logger.warn "[RedmineQboBilling] Could not read custom fields from recent estimates: #{e.message}"
      []
    end

    # Preferences list the custom fields as name/value pairs:
    #   SalesFormsPrefs.UseSalesCustom2  => true       (field 2 is turned on)
    #   SalesFormsPrefs.SalesCustomName2 => "VIN"      (field 2's name)
    # The number is the field's DefinitionId on estimates.
    def parse_custom_fields(entries)
      enabled = {}
      names = {}

      Array(entries).each do |entry|
        case entry.name.to_s
        when /UseSalesCustom(\d+)\z/
          enabled[$1.to_i] = entry.boolean_value.to_s == 'true'
        when /SalesCustomName(\d+)\z/
          names[$1.to_i] = entry.string_value.to_s.strip
        end
      end

      names.keys.sort.filter_map do |id|
        next if names[id].blank? || enabled[id] == false
        { id: id, name: names[id] }
      end
    end
  end
end
