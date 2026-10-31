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
  # What the estimate and invoice editor shows and posts: the header fields and the lines.
  # EstimateWriter and InvoiceWriter turn it into a QuickBooks estimate or invoice and back.
  class EstimateForm
    include ActiveModel::Model
    include ActiveModel::Validations

    # One row of the line table. A row with a product/service is a sales line; a row with only a
    # description (e.g. the estimate notes on the first line) becomes a description-only line.
    # A subtotal row (kind "subtotal") totals the lines above it, back to the previous subtotal.
    # On invoices, a row imported from a QuickBooks time activity keeps its id (time_activity_id) so the
    # invoice line stays linked to it and QuickBooks marks the time as billed.
    class Line
      include ActiveModel::Model

      SUBTOTAL = 'subtotal'.freeze

      # The fields each row posts (the controller permits exactly these)
      PARAMS = %i[id kind item_id item_name description quantity rate taxable time_activity_id].freeze

      attr_accessor :id, :kind, :item_id, :item_name, :description, :quantity, :rate, :taxable, :time_activity_id

      def self.from_params(hash)
        hash = hash.to_h.stringify_keys
        new(
          id: hash['id'].presence,
          kind: hash['kind'].to_s == SUBTOTAL ? SUBTOTAL : nil,
          item_id: hash['item_id'].presence,
          item_name: hash['item_name'].to_s.strip,
          description: hash['description'].to_s.strip,
          quantity: hash['quantity'].to_s.strip,
          rate: hash['rate'].to_s.strip,
          taxable: hash['taxable'].to_s == '1',
          time_activity_id: hash['time_activity_id'].presence
        )
      end

      def quantity_value
        EstimateForm.decimal(quantity)
      end

      def rate_value
        EstimateForm.decimal(rate)
      end

      def subtotal?
        kind == SUBTOTAL
      end

      # Quantity defaults to 1 when only a rate is given, like QuickBooks. Subtotals add nothing themselves.
      def amount
        return BigDecimal('0') if subtotal? || rate_value.nil?
        ((quantity_value || BigDecimal('1')) * rate_value).round(2)
      end

      def taxable?
        taxable == true || taxable.to_s == '1' || taxable.to_s == 'true'
      end

      def item?
        !subtotal? && item_id.present?
      end

      # No product and no price: a note line
      def description_only?
        !subtotal? && !item? && rate_value.nil?
      end

      # Empty rows (e.g. the spare row at the bottom of the table) are dropped
      def blank?
        !subtotal? && !item? && item_name.blank? && description.blank? && rate.blank?
      end

      # Typed in the product box but never picked from the list
      def unmatched_item?
        !subtotal? && !item? && item_name.present?
      end

      def number_invalid?
        return false if subtotal?
        (quantity.present? && quantity_value.nil?) || (rate.present? && rate_value.nil?)
      end
    end

    # due_date is an invoice's; expiration_date an estimate's
    HEADER_ATTRIBUTES = %i[customer_id customer_name email txn_date expiration_date due_date doc_number vin mileage customer_memo private_note].freeze

    # "estimate" or "invoice"
    attr_writer :document

    attr_accessor :id, :sync_token, *HEADER_ATTRIBUTES, :sales_person, :lines,
                  # Invoices: estimates whose lines are on this invoice (they're linked and closed when saved)
                  :linked_estimate_ids,
                  # Read-only details shown on the editor
                  :billing_address, :total, :total_tax, :discount, :email_status, :txn_status, :duplicated_from,
                  :balance, :converted_from,
                  # Estimates: the invoices it's billed on ([[id, number], ...])
                  :invoiced_on,
                  # nil, :bundles (has bundle lines), :linked (an issue is linked to the estimate) or
                  # :paid (a payment is applied to the invoice)
                  :locked

    validate :validate_customer
    validate :validate_lines
    validate :validate_dates
    validate :validate_email
    # Plugins can block a save (e.g. redmine_qbo_vehicles: one vehicle per invoice); see IssueValues
    validate :validate_with_plugins

    def initialize(attributes = {})
      super
      self.lines ||= []
      self.linked_estimate_ids ||= []
    end

    def document
      @document || 'estimate'
    end

    def invoice?
      document == 'invoice'
    end

    # Builds the form from posted params (estimate[...], with lines keyed by row in table order)
    def self.from_params(params, id: nil, document: 'estimate')
      params = params.to_h.stringify_keys
      form = new(id: id.presence, sync_token: params['sync_token'].presence, document: document)
      HEADER_ATTRIBUTES.each { |attr| form.public_send("#{attr}=", params[attr.to_s].to_s.strip) }
      form.total_tax = params['total_tax'].presence
      form.discount = params['discount'].presence
      form.email_status = params['email_status'].presence
      form.txn_status = params['txn_status'].presence
      form.balance = params['balance'].presence
      form.linked_estimate_ids = Array(params['linked_estimate_ids']).map(&:to_s).reject(&:blank?).uniq
      form.lines = params['lines'].to_h.values.map { |row| Line.from_params(row) }
      form
    end

    def self.decimal(value)
      text = value.to_s.strip.delete(',').delete('$')
      return nil if text.empty?
      BigDecimal(text)
    rescue ArgumentError
      nil
    end

    def self.date(value)
      return value if value.is_a?(Date)
      text = value.to_s.strip
      text.empty? ? nil : Date.iso8601(text)
    rescue ArgumentError
      nil
    end

    def persisted?
      id.present?
    end

    def filled_lines
      lines.reject(&:blank?)
    end

    def subtotal
      filled_lines.sum(BigDecimal('0'), &:amount)
    end

    def sent?
      email_status.to_s == 'EmailSent'
    end

    def txn_date_value
      self.class.date(txn_date)
    end

    def expiration_date_value
      self.class.date(expiration_date)
    end

    def due_date_value
      self.class.date(due_date)
    end

    private

    # Messages are added to base so they read as full sentences in Redmine's error box
    def invalid(label_key)
      errors.add(:base, I18n.t(:error_estimate_field_invalid, field: I18n.t(label_key)))
    end

    def validate_customer
      errors.add(:base, I18n.t(:error_estimate_needs_customer)) if customer_id.blank?
    end

    def validate_lines
      if filled_lines.empty?
        errors.add(:base, I18n.t(:error_estimate_needs_a_line))
        return
      end

      filled_lines.each_with_index do |line, index|
        number = index + 1
        errors.add(:base, I18n.t(:error_estimate_line_unmatched_item, line: number, name: line.item_name)) if line.unmatched_item?
        errors.add(:base, I18n.t(:error_estimate_line_number, line: number)) if line.number_invalid?
        errors.add(:base, I18n.t(:error_estimate_line_description, line: number)) if line.description_only? && line.description.blank?
      end
    end

    def validate_dates
      invalid(invoice? ? :label_invoice_date : :label_estimate_date) if txn_date_value.nil?
      invalid(:label_expiration_date) if expiration_date.present? && expiration_date_value.nil?
      invalid(:label_due_date) if due_date.present? && due_date_value.nil?
    end

    def validate_with_plugins
      IssueValues.plugin_errors(self).each { |message| errors.add(:base, message) }
    end

    def validate_email
      return if email.blank?
      # QuickBooks takes several addresses separated by commas
      addresses = email.split(',').map(&:strip)
      invalid(:label_customer_email) unless addresses.all? { |a| a.match?(/\A[^@\s]+@[^@\s]+\z/) }
    end
  end
end
