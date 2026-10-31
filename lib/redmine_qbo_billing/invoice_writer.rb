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
  # Reads QuickBooks invoices into an EstimateForm (document "invoice") and writes forms back as invoices.
  # Lines, subtotals, discounts, custom fields and addresses work exactly as on estimates (EstimateWriter).
  #
  # On top of that an invoice can take lines from elsewhere:
  # * an estimate converted to an invoice, or open estimates imported into it (e.g. the ones
  #   redmine_qbo_lineitems makes for parts that weren't quoted). Those estimates are linked to the invoice
  #   and closed when it's saved.
  # * billable QuickBooks time activities (the ones redmine_qbo makes from an issue's time entries). Each
  #   becomes a line linked to its time activity, so QuickBooks marks the time as billed.
  #
  # An invoice with a payment applied to it is read-only, so a paid invoice can't be changed under the payment.
  module InvoiceWriter
    Error = EstimateWriter::Error
    Conflict = EstimateWriter::Conflict

    ESTIMATE = 'Estimate'.freeze
    TIME_ACTIVITY = EstimateWriter::TIME_ACTIVITY
    # Estimates in these states can still be imported (Converted/Closed ones are already invoiced, Rejected ones lost)
    OPEN_ESTIMATE_STATUSES = ['', 'Pending', 'Accepted'].freeze
    # How QuickBooks marks an invoiced estimate: Converted when it made the invoice, Closed when closed by hand
    BILLED_ESTIMATE_STATUSES = EstimateWriter::BILLED_STATUSES
    # How far back to look for billable time if QuickBooks won't filter time activities by customer
    TIME_LOOKBACK = 400

    module_function

    def writer
      EstimateWriter
    end

    # A blank invoice for the customer, dated today
    def new_form(customer: nil, user: User.current)
      EstimateForm.new(
        document: 'invoice',
        customer_id: customer&.id,
        customer_name: customer&.name,
        email: writer.customer_email(customer),
        billing_address: writer.customer_address(customer),
        txn_date: user.today.iso8601,
        sales_person: user.name,
        customer_memo: Company.invoice_message,
        lines: Array.new(2) { EstimateForm::Line.new(quantity: '', taxable: true) }
      )
    end

    # A new invoice from an estimate, like QuickBooks' "Create invoice" on an estimate: the estimate's
    # customer, lines, subtotals and custom fields. The estimate is linked and closed when the invoice is saved.
    def from_estimate(estimate_id, user: User.current)
      remote = QboEstimateService.with_service { |service| service.fetch_by_id(estimate_id) }
      raise Error, I18n.t(:notice_estimate_not_found) unless remote
      # An estimate is billed once
      billed = billing_error(remote)
      raise Error, billed if billed

      source = writer.form_from_remote(remote)
      customer = Customer.find_by(id: source.customer_id)
      new_form(customer: customer, user: user).tap do |form|
        form.customer_name = source.customer_name if customer.nil?
        form.customer_id = source.customer_id
        form.email = source.email.presence || form.email
        form.billing_address = source.billing_address.presence || form.billing_address
        # The estimate's custom fields; ones it leaves blank come from plugins for its work orders (e.g.
        # redmine_qbo_vehicles: their VIN)
        defaults = RedmineQboBilling.field_defaults(customer, issues: Issue.where(estimate_id: source.id.to_s).to_a)
        form.custom_fields = defaults.merge(source.custom_fields.reject { |_, value| value.blank? })
        # The estimate's writer sells the job; with no one on the estimate, whoever writes the invoice
        form.sales_person = source.sales_person.presence || user.name
        form.private_note = source.private_note
        form.lines = copy_lines(source.lines)
        form.linked_estimate_ids = [source.id.to_s]
        form.converted_from = source.doc_number
      end
    end

    def load(id)
      remote = QboInvoiceService.with_service { |service| service.fetch_by_id(id) }
      raise Error, I18n.t(:notice_invoice_not_found) unless remote
      form_from_remote(remote)
    end

    # Creates or updates the invoice in QuickBooks, closes the estimates it was made from, and returns the
    # saved QuickBooks invoice. The sales person is the one on the estimate it was made from (the first linked
    # estimate that names one), or else the user who creates it; editing keeps the original one.
    def save(form, user: User.current)
      customer = Customer.find_by(id: form.customer_id)
      raise Error, I18n.t(:error_estimate_needs_customer) unless customer

      saved = QboInvoiceService.with_service do |service|
        if form.persisted?
          remote = service.fetch_by_id(form.id)
          raise Error, I18n.t(:notice_invoice_not_found) unless remote
          raise Conflict, I18n.t(:error_invoice_changed_in_quickbooks) if remote.sync_token.to_s != form.sync_token.to_s
          raise Error, I18n.t(:error_invoice_has_bundles) if writer.group_lines?(remote)
          raise Error, I18n.t(:error_invoice_paid) if paid?(remote)
          check_not_billed(form.linked_estimate_ids - linked_ids(remote, ESTIMATE))

          invoice = Quickbooks::Model::Invoice.new
          invoice.id = remote.id
          invoice.sync_token = remote.sync_token
          apply(form, invoice, customer: customer, remote: remote, user: user)
          service.update(invoice, sparse: true)
        else
          check_not_billed(form.linked_estimate_ids)
          invoice = Quickbooks::Model::Invoice.new
          apply(form, invoice, customer: customer, remote: nil, user: user,
                sales_person: estimate_sales_person(form.linked_estimate_ids))
          service.create(invoice)
        end
      end
      raise Error, I18n.t(:error_invoice_not_saved) unless saved

      sync_local(saved)
      close_estimates(linked_ids(saved, ESTIMATE).presence || form.linked_estimate_ids)
      saved
    end

    def send_email(id, email)
      sent = QboInvoiceService.with_service { |service| service.send_invoice(id, email) }
      raise Error, I18n.t(:error_invoice_not_sent) unless sent
      sent
    end

    # ---- QuickBooks invoice -> form ----

    def form_from_remote(remote)
      EstimateForm.new(
        document: 'invoice',
        id: remote.id.to_s,
        sync_token: remote.sync_token.to_s,
        customer_id: remote.customer_ref&.value.to_s,
        customer_name: remote.customer_ref&.name.presence || Customer.find_by(id: remote.customer_ref&.value)&.name,
        email: remote.bill_email&.address.to_s,
        billing_address: writer.format_address(remote.billing_address),
        txn_date: remote.txn_date&.iso8601,
        due_date: remote.due_date&.iso8601,
        doc_number: remote.doc_number.to_s,
        sales_person: writer.custom_value(remote, Company.sales_person_field, Company::SALES_PERSON_NAME),
        custom_fields: writer.custom_field_values(remote),
        customer_memo: remote.customer_memo.to_s,
        private_note: remote.private_note.to_s,
        lines: writer.tidy_subtotals(Array(remote.line_items).filter_map { |line| writer.line_from_remote(line) }),
        linked_estimate_ids: linked_ids(remote, ESTIMATE),
        total: remote.total,
        total_tax: remote.txn_tax_detail&.total_tax,
        discount: writer.discount_total(remote),
        balance: remote.balance,
        email_status: remote.email_status.to_s,
        locked: (:bundles if writer.group_lines?(remote)) || (:paid if paid?(remote))
      )
    end

    # A payment is applied once the balance is less than the total
    def paid?(remote)
      return false if remote.balance.nil? || remote.total.nil?
      BigDecimal(remote.balance.to_s) < BigDecimal(remote.total.to_s)
    end

    def linked_ids(remote, type)
      Array(remote&.linked_transactions).select { |t| t.txn_type.to_s == type }.map { |t| t.txn_id.to_s }.uniq
    end

    # ---- form -> QuickBooks invoice ----

    def apply(form, invoice, customer:, remote:, user:, sales_person: nil)
      invoice.customer_id = customer.id
      if remote.nil? || remote.customer_ref&.value.to_s != customer.id.to_s
        address = writer.customer_details(customer)&.billing_address
        invoice.billing_address = address if address
      end

      invoice.bill_email = Quickbooks::Model::EmailAddress.new(form.email) if form.email.present?
      invoice.txn_date = form.txn_date_value
      # Left out when empty: QuickBooks works it out from the customer's terms
      invoice.due_date = form.due_date_value if form.due_date_value
      invoice.doc_number = writer.next_doc_number(Invoice) if remote.nil? && Company.custom_txn_numbers?
      invoice.customer_memo = form.customer_memo.to_s
      invoice.private_note = form.private_note.to_s
      invoice.custom_fields = writer.build_custom_fields(form, remote, user, sales_person: sales_person)
      invoice.line_items = writer.build_lines(form, remote)
      invoice.linked_transactions = header_links(form, remote)
      invoice
    end

    # The invoice-level links: the estimates it was made from, and every time activity a line bills
    # (QuickBooks wants time linked both on the line and on the invoice)
    def header_links(form, remote)
      estimates = (linked_ids(remote, ESTIMATE) + form.linked_estimate_ids).uniq
      times = form.filled_lines.filter_map(&:time_activity_id).map(&:to_s).uniq
      estimates.map { |id| link(id, ESTIMATE) } + times.map { |id| link(id, TIME_ACTIVITY) }
    end

    def link(id, type)
      Quickbooks::Model::LinkedTransaction.new(txn_id: id.to_s, txn_type: type)
    end

    # The sales person on the first of the estimates that names one (estimates redmine_qbo_lineitems makes
    # have none), so the invoice credits whoever wrote the estimate
    def estimate_sales_person(estimate_ids)
      field = Company.sales_person_field
      return nil if field.nil? || Array(estimate_ids).empty?

      QboEstimateService.with_service do |service|
        Array(estimate_ids).each do |id|
          estimate = service.fetch_by_id(id)
          name = estimate && writer.custom_value(estimate, field, Company::SALES_PERSON_NAME)
          return name if name.present?
        end
        nil
      end
    rescue StandardError => e
      Rails.logger.warn "[RedmineQboBilling] Could not read the estimate's sales person: #{e.message}"
      nil
    end

    # ---- billing an estimate once ----

    # Why the estimate can't be billed, or nil: it's already on an invoice (linked to one, or closed, which is
    # how QuickBooks marks an invoiced estimate), or the customer rejected it
    def billing_error(estimate)
      number = estimate.doc_number.to_s
      invoice_id = linked_ids(estimate, 'Invoice').first
      if invoice_id
        I18n.t(:error_estimate_already_invoiced, number: number, invoice: invoice_number(invoice_id))
      elsif BILLED_ESTIMATE_STATUSES.include?(estimate.txn_status.to_s)
        I18n.t(:error_estimate_closed_billed, number: number, status: estimate.txn_status.to_s)
      elsif estimate.txn_status.to_s == 'Rejected'
        I18n.t(:error_estimate_rejected, number: number)
      end
    end

    # Checked against QuickBooks when saving, since an estimate can be invoiced elsewhere (another tab, another
    # user, QuickBooks itself) after the invoice page was opened. Estimates already on this invoice aren't checked.
    def check_not_billed(estimate_ids)
      ids = Array(estimate_ids).map(&:to_s).reject(&:blank?).uniq
      return if ids.empty?

      errors = QboEstimateService.with_service do |service|
        ids.filter_map do |id|
          estimate = service.fetch_by_id(id)
          estimate ? billing_error(estimate) : I18n.t(:notice_estimate_not_found)
        end
      end
      raise Error, errors.join(' ') if errors.any?
    end

    # The invoice's number when it's synced locally, else its QuickBooks id
    def invoice_number(invoice_id)
      Invoice.find_by(id: invoice_id)&.doc_number.presence || invoice_id.to_s
    rescue StandardError
      invoice_id.to_s
    end

    # Marks the estimates as closed (invoiced), as QuickBooks does when it converts one. Done separately
    # so it also happens if QuickBooks doesn't close a linked estimate by itself.
    def close_estimates(ids)
      Array(ids).uniq.each do |id|
        QboEstimateService.with_service do |service|
          estimate = service.fetch_by_id(id)
          # Already Converted or Closed is left as QuickBooks set it
          next if estimate.nil? || BILLED_ESTIMATE_STATUSES.include?(estimate.txn_status.to_s)

          service.update(writer.status_update(estimate, 'Closed'), sparse: true)
        end
        EstimateSyncService.new.sync_by_id(id)
      rescue StandardError => e
        Rails.logger.warn "[RedmineQboBilling] Could not close estimate #{id}: #{e.message}"
      end
    end

    # ---- importing ----

    # What can be pulled into an invoice for the customer: billable time and open estimates, and the custom
    # field values plugins give for their work orders (and for issues already on the invoice: issue_ids)
    def import_options(customer, issue_ids: [])
      times = open_time_activities(customer)
      estimates = open_estimates(customer)
      ids = (times.map { |t| t[:issue_id] } + estimates.map { |e| e[:issue_id] } + Array(issue_ids)).compact.map(&:to_s).uniq
      issues = ids.empty? ? [] : Issue.where(id: ids).to_a
      { time_activities: times, estimates: estimates, issue_values: IssueValues.by_issue(issues) }
    end

    # The customer's QuickBooks time activities that are still billable (not yet on an invoice)
    def open_time_activities(customer)
      activities = QboConnectionService.with_qbo_service(entity: 'TimeActivity') do |service|
        begin
          service.query("SELECT * FROM TimeActivity WHERE CustomerRef = '#{customer.id.to_i}' ORDERBY TxnDate", per_page: 1000).entries
        rescue StandardError
          # Not every company lets time be filtered by customer: look at recent time instead
          since = (Date.today - TIME_LOOKBACK).iso8601
          service.query("SELECT * FROM TimeActivity WHERE TxnDate >= '#{since}' ORDERBY TxnDate", per_page: 1000).entries
        end
      end

      Array(activities).select { |a| a.customer_ref&.value.to_s == customer.id.to_s && a.billable_status.to_s == 'Billable' }
                       .map { |a| time_activity_hash(a) }
    end

    def time_activity_hash(activity)
      hours = activity_hours(activity)
      rate = EstimateForm.decimal(activity.hourly_rate) || BigDecimal('0')
      item = Item.find_by(id: activity.item_ref&.value) if activity.item_ref&.value.present?
      {
        id: activity.id.to_s,
        date: activity.txn_date.to_s,
        employee: activity.employee_ref&.name || activity.vendor_ref&.name,
        item_id: activity.item_ref&.value.to_s.presence,
        item_name: activity.item_ref&.name.presence || item&.name,
        description: activity.description.to_s,
        issue_id: issue_reference(activity.description),
        quantity: writer.plain_number(hours),
        rate: writer.plain_number(rate),
        amount: (hours * rate).round(2).to_s('F'),
        taxable: item ? item.taxable != false : false
      }
    end

    # Hours and minutes, or start and end time less the break
    def activity_hours(activity)
      if activity.hours || activity.minutes
        (BigDecimal(activity.hours.to_i.to_s) + BigDecimal(activity.minutes.to_i.to_s) / 60).round(4)
      elsif activity.start_time && activity.end_time
        minutes = ((activity.end_time.to_time - activity.start_time.to_time) / 60).round -
                  (activity.break_hours.to_i * 60 + activity.break_minutes.to_i)
        (BigDecimal([minutes, 0].max.to_s) / 60).round(4)
      else
        BigDecimal('0')
      end
    end

    # The customer's open estimates, each with its lines ready to add to an invoice
    def open_estimates(customer)
      estimates = QboEstimateService.with_service do |service|
        service.query("SELECT * FROM Estimate WHERE CustomerRef = '#{customer.id.to_i}' ORDERBY TxnDate DESC", per_page: 100).entries
      end

      Array(estimates).select { |e| billing_error(e).nil? && OPEN_ESTIMATE_STATUSES.include?(e.txn_status.to_s) && !writer.group_lines?(e) }.map do |e|
        lines = writer.tidy_subtotals(Array(e.line_items).filter_map { |line| writer.line_from_remote(line) })
        linked_issue = writer.linked_issues(e.id).first
        {
          id: e.id.to_s,
          doc_number: e.doc_number.to_s,
          date: e.txn_date.to_s,
          total: e.total.to_s,
          issue: linked_issue&.then { |i| "#{i.tracker} ##{i.id}: #{i.subject}" },
          # Lines from this estimate go next to the invoice's time for the same issue
          issue_id: issue_reference(lines.detect { |l| l.description.present? }&.description) || linked_issue&.id&.to_s,
          # The estimate's own custom field values (plugins' editor scripts may use them, e.g. its VIN)
          custom_fields: writer.custom_field_values(e),
          lines: lines.map { |l| line_hash(l) }
        }
      end
    end

    def issue_reference(text)
      IssueValues.issue_reference(text)
    end

    def line_hash(line)
      { kind: line.kind, item_id: line.item_id, item_name: line.item_name, description: line.description,
        quantity: line.quantity, rate: line.rate, taxable: line.taxable? }
    end

    # ---- helpers ----

    # Lines copied to a new document: no line ids, everything else as it was
    def copy_lines(lines)
      lines.map do |line|
        EstimateForm::Line.new(kind: line.kind, item_id: line.item_id, item_name: line.item_name,
                               description: line.description, quantity: line.quantity, rate: line.rate,
                               taxable: line.taxable, time_activity_id: line.time_activity_id)
      end
    end

    def sync_local(saved)
      InvoiceSyncService.new.sync_by_id(saved.id)
    rescue StandardError => e
      Rails.logger.warn "[RedmineQboBilling] Saved invoice #{saved.id} but could not sync it locally: #{e.message}"
    end
  end
end
