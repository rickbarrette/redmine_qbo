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
  # Reads QuickBooks estimates into an EstimateForm and writes forms back as estimates.
  #
  # Subtotal rows are saved the way QuickBooks saves the subtotals added on its own estimate screen: a
  # description-only line reading "Subtotal: $342.60", which prints where it was placed. The subtotal
  # QuickBooks always adds after the last line isn't shown (QuickBooks adds it back). Discount lines are kept
  # as they are, and estimates with bundle (group) lines are read-only so a bundle can't be broken up.
  #
  # Estimate numbers are never typed: QuickBooks numbers new estimates, or when its custom transaction
  # numbers are on, the next number is filled in when the estimate is created.
  module EstimateWriter
    class Error < StandardError; end

    # The estimate was saved in QuickBooks (by someone else, or in another tab) after the form was opened
    class Conflict < Error; end

    # How QuickBooks writes a subtotal line, e.g. "Subtotal: $1,342.60"
    SUBTOTAL_TEXT = /\ASubtotal:\s*-?\$?-?[\d,]*(\.\d+)?\s*\z/i

    module_function

    # A blank estimate for the customer, filled in the way QuickBooks starts a new estimate
    def new_form(customer: nil, user: User.current)
      EstimateForm.new(
        customer_id: customer&.id,
        customer_name: customer&.name,
        email: customer_email(customer),
        billing_address: customer_address(customer),
        txn_date: user.today.iso8601,
        expiration_date: default_expiration_date(user.today)&.iso8601,
        sales_person: user.name,
        customer_memo: Company.estimate_message,
        lines: Array.new(2) { EstimateForm::Line.new(quantity: '', taxable: true) }
      )
    end

    # Creates an estimate for another plugin (e.g. redmine_qbo_lineitems billing an issue's line items), so
    # estimates are only ever built here. Each line is a hash of :description, :item_id, :quantity, :rate,
    # :taxable (a line with only a description is a note line). Returns the saved QuickBooks estimate.
    def create_estimate(customer:, lines:, private_note: nil, vin: nil, mileage: nil, user: nil, txn_date: Date.today)
      form = EstimateForm.new(
        customer_id: customer.id,
        customer_name: customer.name,
        email: customer_email(customer),
        txn_date: txn_date.iso8601,
        expiration_date: default_expiration_date(txn_date)&.iso8601,
        vin: vin.to_s,
        mileage: mileage.to_s,
        customer_memo: Company.estimate_message,
        private_note: private_note.to_s,
        lines: lines.map do |line|
          line = line.to_h.symbolize_keys
          EstimateForm::Line.new(
            item_id: line[:item_id]&.to_s.presence,
            description: line[:description].to_s,
            quantity: plain_number(line[:quantity]),
            rate: plain_number(line[:rate]),
            taxable: line.fetch(:taxable, true) ? true : false
          )
        end
      )
      save(form, user: user)
    end

    # A new estimate copied from an existing one: same customer, lines, VIN and messages, dated today, with a
    # new number, the current user as sales person, and no discounts or bundles (those stay in QuickBooks)
    def duplicate_form(id, user: User.current)
      source = load(id)
      today = user.today
      EstimateForm.new(
        customer_id: source.customer_id,
        customer_name: source.customer_name,
        email: source.email,
        billing_address: source.billing_address,
        txn_date: today.iso8601,
        expiration_date: default_expiration_date(today)&.iso8601,
        sales_person: user.name,
        vin: source.vin,
        mileage: source.mileage,
        customer_memo: source.customer_memo,
        private_note: source.private_note,
        lines: source.lines.map do |line|
          EstimateForm::Line.new(kind: line.kind, item_id: line.item_id, item_name: line.item_name,
                                 description: line.description, quantity: line.quantity, rate: line.rate,
                                 taxable: line.taxable)
        end
      ).tap { |form| form.duplicated_from = source.doc_number }
    end

    # Issues linked to the estimate (redmine_qbo's issue estimate field)
    def linked_issues(estimate_id)
      return Issue.none if estimate_id.blank?
      Issue.where(estimate_id: estimate_id.to_s)
    end

    # Loads the estimate from QuickBooks for editing
    def load(id)
      remote = QboEstimateService.with_service { |service| service.fetch_by_id(id) }
      raise Error, I18n.t(:notice_estimate_not_found) unless remote
      form_from_remote(remote)
    end

    # Creates or updates the estimate in QuickBooks and returns the saved QuickBooks estimate.
    # The sales person is the user who creates the estimate; editing keeps the original one.
    def save(form, user: User.current)
      customer = Customer.find_by(id: form.customer_id)
      raise Error, I18n.t(:error_estimate_needs_customer) unless customer

      saved = QboEstimateService.with_service do |service|
        if form.persisted?
          remote = service.fetch_by_id(form.id)
          raise Error, I18n.t(:notice_estimate_not_found) unless remote
          raise Conflict, I18n.t(:error_estimate_changed_in_quickbooks) if remote.sync_token.to_s != form.sync_token.to_s
          raise Error, I18n.t(:error_estimate_billed) if billed?(remote)
          raise Error, I18n.t(:error_estimate_has_bundles) if group_lines?(remote)
          raise Error, I18n.t(:error_estimate_linked_to_issues) if linked_issues(form.id).any?

          estimate = Quickbooks::Model::Estimate.new
          estimate.id = remote.id
          estimate.sync_token = remote.sync_token
          apply(form, estimate, customer: customer, remote: remote, user: user)
          service.update(estimate, sparse: true)
        else
          estimate = Quickbooks::Model::Estimate.new
          apply(form, estimate, customer: customer, remote: nil, user: user)
          service.create(estimate)
        end
      end
      raise Error, I18n.t(:error_estimate_not_saved) unless saved

      sync_local(saved)
      saved
    end

    # The VIN on an estimate, read with QuickBooks' newer custom fields (a plain fetch, e.g. Estimate#details,
    # leaves them out). Cached for a minute, since creating issues asks once per issue.
    def vin_for(estimate_id)
      return nil if estimate_id.blank?

      Rails.cache.fetch("redmine_qbo:estimate_vin:#{estimate_id}", expires_in: 1.minute) do
        remote = QboEstimateService.with_service { |service| service.fetch_by_id(estimate_id) }
        remote ? custom_value(remote, Company.vin_field, Company::VIN_NAME).to_s.strip : ''
      end.presence
    rescue StandardError => e
      Rails.logger.warn "[RedmineQboBilling] Could not read estimate #{estimate_id}'s VIN: #{e.message}"
      nil
    end

    # Emails the estimate; QuickBooks uses its own estimate email template
    def send_email(id, email)
      sent = QboEstimateService.with_service { |service| service.send_estimate(id, email) }
      raise Error, I18n.t(:error_estimate_not_sent) unless sent
      sent
    end

    # ---- QuickBooks estimate -> form ----

    # Statuses QuickBooks gives an estimate that has been turned into an invoice
    BILLED_STATUSES = %w[Converted Closed].freeze

    # True once the estimate is billed: converted or closed, or linked to an invoice. Billed estimates (including
    # redmine_qbo_lineitems' once they're invoiced) can't be changed here.
    def billed?(remote)
      BILLED_STATUSES.include?(remote.txn_status.to_s) ||
        Array(remote.linked_transactions).any? { |t| t.txn_type.to_s == 'Invoice' }
    end

    def form_from_remote(remote)
      EstimateForm.new(
        id: remote.id.to_s,
        sync_token: remote.sync_token.to_s,
        customer_id: remote.customer_ref&.value.to_s,
        customer_name: remote.customer_ref&.name.presence || Customer.find_by(id: remote.customer_ref&.value)&.name,
        email: remote.bill_email&.address.to_s,
        billing_address: format_address(remote.billing_address),
        txn_date: remote.txn_date&.iso8601,
        expiration_date: remote.expiration_date&.iso8601,
        doc_number: remote.doc_number.to_s,
        sales_person: custom_value(remote, Company.sales_person_field, Company::SALES_PERSON_NAME),
        vin: custom_value(remote, Company.vin_field, Company::VIN_NAME),
        mileage: custom_value(remote, Company.mileage_field, Company::MILEAGE_NAME),
        customer_memo: remote.customer_memo.to_s,
        private_note: remote.private_note.to_s,
        lines: tidy_subtotals(Array(remote.line_items).filter_map { |line| line_from_remote(line) }),
        total: remote.total,
        total_tax: remote.txn_tax_detail&.total_tax,
        discount: discount_total(remote),
        email_status: remote.email_status.to_s,
        txn_status: remote.txn_status.to_s,
        invoiced_on: Array(remote.linked_transactions).select { |t| t.txn_type.to_s == 'Invoice' }.map { |t|
          [t.txn_id.to_s, InvoiceWriter.invoice_number(t.txn_id)]
        }.uniq,
        # Read-only once it's billed (converted, closed or on an invoice), when it has bundles, or once an issue
        # is linked to it (the work is under way)
        locked: (:billed if billed?(remote)) || (:bundles if group_lines?(remote)) ||
                (:linked if linked_issues(remote.id).any?)
      )
    end

    def line_from_remote(line)
      if line.sales_item?
        detail = line.sales_line_item_detail
        EstimateForm::Line.new(
          id: line.id.to_s,
          item_id: detail&.item_ref&.value.to_s.presence,
          item_name: detail&.item_ref&.name.to_s,
          description: line.description.to_s,
          quantity: plain_number(detail&.quantity),
          rate: plain_number(detail&.unit_price),
          taxable: detail&.tax_code_ref&.value.to_s == 'TAX',
          time_activity_id: linked_time_activity_id(line)
        )
      elsif line.description_only? && line.description.to_s.strip.match?(SUBTOTAL_TEXT)
        EstimateForm::Line.new(id: line.id.to_s, kind: EstimateForm::Line::SUBTOTAL)
      elsif line.description_only?
        EstimateForm::Line.new(id: line.id.to_s, description: line.description.to_s)
      end
      # QuickBooks' own subtotal (always after the last line), discount and group lines aren't edited here
    end

    # The custom field's value, found by the field QuickBooks' preferences name, or by name on the estimate
    def custom_value(remote, field, name_pattern)
      fields = Array(remote.custom_fields)
      match = fields.detect { |f| field && f.id.to_i == field.id.to_i } ||
              fields.detect { |f| f.name.to_s =~ name_pattern && (name_pattern == Company::VIN_NAME || f.name.to_s !~ Company::VIN_NAME) }
      match&.string_value.to_s
    end

    # ---- form -> QuickBooks estimate ----

    def apply(form, estimate, customer:, remote:, user:)
      estimate.customer_id = customer.id
      # QuickBooks copies the customer's billing address only when an estimate is created
      if remote.nil? || remote.customer_ref&.value.to_s != customer.id.to_s
        address = customer_details(customer)&.billing_address
        estimate.billing_address = address if address
      end

      estimate.bill_email = Quickbooks::Model::EmailAddress.new(form.email) if form.email.present?
      estimate.txn_date = form.txn_date_value
      estimate.expiration_date = form.expiration_date_value
      # Numbers aren't typed. With QuickBooks' custom transaction numbers on, it doesn't number estimates
      # made by apps, so the next number is filled in here.
      estimate.doc_number = next_doc_number if remote.nil? && Company.custom_txn_numbers?
      estimate.customer_memo = form.customer_memo.to_s
      estimate.private_note = form.private_note.to_s
      estimate.custom_fields = build_custom_fields(form, remote, user)
      estimate.line_items = build_lines(form, remote)
      estimate
    end

    # Keeps every custom field already on the estimate, then sets the VIN, and the sales person on create
    # (left empty for estimates made without a user, e.g. by a background job)
    # sales_person: who to name instead of the user (e.g. an invoice names the estimate's sales person)
    def build_custom_fields(form, remote, user, sales_person: nil)
      fields = {}
      Array(remote&.custom_fields).each do |f|
        next unless f.type.to_s == 'StringType' || f.string_value.present?
        fields[f.id.to_i] = string_field(f.id, f.name, f.string_value)
      end

      if (vin = Company.vin_field)
        fields[vin.id.to_i] = string_field(vin.id, vin.name, form.vin.to_s.strip.upcase)
      end

      if (mileage = Company.mileage_field)
        fields[mileage.id.to_i] = string_field(mileage.id, mileage.name, form.mileage.to_s.strip)
      end

      sales = Company.sales_person_field
      name = sales_person.presence || user&.name
      if sales && remote.nil? && name.present?
        fields[sales.id.to_i] = string_field(sales.id, sales.name, name)
      end

      fields.values
    end

    def string_field(id, name, value)
      field = Quickbooks::Model::CustomField.new
      field.id = id.to_i
      field.name = name
      field.type = 'StringType'
      field.string_value = value.to_s
      field
    end

    def build_lines(form, remote)
      remote_ids = Array(remote&.line_items).map { |l| l.id.to_s }
      section = BigDecimal('0')
      lines = tidy_subtotals(form.filled_lines).map.with_index(1) do |line, number|
        built = build_line(line, number, keep_id: remote_ids.include?(line.id.to_s), section_total: section)
        section = line.subtotal? ? BigDecimal('0') : section + (line.description_only? ? BigDecimal('0') : built.amount)
        built
      end

      # Discounts keep their place after the lines
      Array(remote&.line_items).select(&:discount_item?).each do |discount|
        discount.line_num = lines.size + 1
        lines << discount
      end
      lines
    end

    def build_line(line, number, keep_id:, section_total: BigDecimal('0'))
      remote = Quickbooks::Model::InvoiceLineItem.new
      remote.id = line.id if keep_id
      remote.line_num = number

      # Saved like QuickBooks saves its subtotals: a description line with the total of its section
      if line.subtotal?
        remote.description = subtotal_text(section_total)
        remote.description_only!
        return remote
      end

      remote.description = line.description

      if line.description_only?
        remote.description_only!
        return remote
      end

      rate = line.rate_value
      rate ||= Item.find_by(id: line.item_id)&.unit_price if line.item?
      rate ||= BigDecimal('0')
      quantity = line.quantity_value || BigDecimal('1')

      remote.amount = (quantity * rate).round(2)
      link_time_activity(remote, line.time_activity_id)
      remote.sales_item! do |detail|
        detail.item_ref = Quickbooks::Model::BaseReference.new(line.item_id) if line.item?
        detail.quantity = quantity
        detail.unit_price = rate
        detail.tax_code_ref = Quickbooks::Model::BaseReference.new(line.taxable? ? 'TAX' : 'NON')
      end
      remote
    end

    # ---- helpers ----

    TIME_ACTIVITY = 'TimeActivity'.freeze

    # The time activity an invoice line bills, if any
    def linked_time_activity_id(line)
      return nil unless line.respond_to?(:linked_transactions)
      Array(line.linked_transactions).detect { |t| t.txn_type.to_s == TIME_ACTIVITY }&.txn_id&.to_s
    end

    # Links an invoice line to the time activity it bills (TxnLineId is always 1 for time activities)
    def link_time_activity(remote_line, time_activity_id)
      return if time_activity_id.blank? || !remote_line.respond_to?(:linked_transactions=)
      remote_line.linked_transactions = [
        Quickbooks::Model::LinkedTransaction.new(txn_id: time_activity_id.to_s, txn_type: TIME_ACTIVITY, txn_line_id: '1')
      ]
    end

    # Drops subtotals with nothing to total (at the top, or right after another subtotal)
    def tidy_subtotals(lines)
      tidy = []
      lines.each do |line|
        next if line.subtotal? && (tidy.empty? || tidy.last.subtotal?)
        tidy << line
      end
      tidy
    end

    # "Subtotal: $1,342.60", as QuickBooks writes it
    def subtotal_text(amount)
      value = BigDecimal(amount.to_s).round(2)
      whole, cents = format('%.2f', value.abs).split('.')
      "Subtotal: #{'-' if value.negative?}$#{whole.reverse.scan(/\d{1,3}/).join(',').reverse}.#{cents}"
    end

    # Discount lines aren't edited here but count toward the total shown
    def discount_total(remote)
      discounts = Array(remote.line_items).select(&:discount_item?)
      discounts.empty? ? nil : discounts.sum(BigDecimal('0')) { |l| l.amount || BigDecimal('0') }
    end

    def group_lines?(remote)
      Array(remote.line_items).any?(&:group_line_detail?)
    end

    # Updates the local estimate record so it shows on the customer page right away
    def sync_local(saved)
      EstimateSyncService.new.sync_by_id(saved.id)
    rescue StandardError => e
      Rails.logger.warn "[RedmineQboBilling] Saved estimate #{saved.id} but could not sync it locally: #{e.message}"
    end

    # The plugin setting "Estimates expire after (days)"; blank or 0 leaves the expiration date empty
    def expiration_days
      Setting.plugin_redmine_qbo['expiration_days'].to_i
    rescue StandardError
      0
    end

    def default_expiration_date(from)
      expiration_days.positive? ? from + expiration_days : nil
    end

    # One more than the highest estimate (or invoice) number used so far
    def next_doc_number(model = Estimate)
      numbers = model.order(id: :desc).limit(500).pluck(:doc_number).filter_map { |n| Integer(n.to_s, 10) rescue nil }
      numbers.empty? ? nil : (numbers.max + 1).to_s
    end

    def customer_details(customer)
      customer&.details
    rescue StandardError => e
      Rails.logger.warn "[RedmineQboBilling] Could not load customer #{customer&.id} from QuickBooks: #{e.message}"
      nil
    end

    def customer_email(customer)
      customer_details(customer)&.email_address&.address.to_s
    end

    def customer_address(customer)
      format_address(customer_details(customer)&.billing_address)
    end

    # Address lines as QuickBooks prints them: street lines, then "City, ST 12345"
    def format_address(address)
      return '' unless address

      street = [address.line1, address.line2, address.line3, address.line4, address.line5].map { |l| l.to_s.strip }.reject(&:empty?)
      region = [address.country_sub_division_code, address.postal_code].map { |l| l.to_s.strip }.reject(&:empty?).join(' ')
      locality = [address.city.to_s.strip, region].reject(&:empty?).join(', ')
      (street + [locality]).reject(&:empty?).join("\n")
    end

    # 2.0 -> "2", 12.50 -> "12.5"; the editor formats rates for display
    def plain_number(value)
      return '' if value.nil? || value.to_s.strip.empty?
      BigDecimal(value.to_s).to_s('F').sub(/\.0+\z/, '').sub(/(\.\d*?)0+\z/, '\1')
    end
  end
end
