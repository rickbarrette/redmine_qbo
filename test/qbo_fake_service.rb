#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Stands in for QuickBooks in the estimate, invoice and payment writer tests: one in-memory service answers
# QboEstimateService.with_service, QboInvoiceService.with_service and QboConnectionService.with_qbo_service.
module QboFakeServiceHelper
  class FakeService
    attr_reader :records, :created, :updated, :sent, :queries, :entities, :customers
    # query_results: { "SQL fragment" or entity name => [records] }; fail_query: a regexp of queries to refuse
    attr_accessor :query_results, :fail_query, :pdf_body

    def initialize(*records)
      @records = {}
      records.each { |record| add(record) }
      @created = []
      @updated = []
      @sent = []
      @queries = []
      @entities = []
      @query_results = {}
      @customers = {}
    end

    def add(record)
      @records[record.id.to_s] = record
      record
    end

    # Local models' details (Customer#details, Item#details...) are looked up through with_qbo_service; they
    # get a blank QuickBooks record unless one was added to customers
    DETAIL_ENTITIES = %w[Customer Item Account Employee].freeze

    def fetch_by_id(id)
      return records[id.to_s] if records.key?(id.to_s)

      entity = entities.last.to_s
      return customers[id.to_s] ||= Quickbooks::Model::Customer.new if entity == 'Customer'
      return "Quickbooks::Model::#{entity}".constantize.new if DETAIL_ENTITIES.include?(entity)

      nil
    end

    def create(doc)
      doc.id ||= (5000 + created.size).to_s
      doc.sync_token = 0
      doc.doc_number ||= "N#{doc.id}" if doc.respond_to?(:doc_number=)
      created << doc
      add(doc)
    end

    def update(doc, sparse: false)
      doc.sync_token = doc.sync_token.to_i + 1
      updated << doc
      add(doc)
    end

    def send_document(id, email)
      sent << [id.to_s, email]
      records[id.to_s]
    end
    alias send_estimate send_document
    alias send_invoice send_document

    def query(sql = nil, per_page: nil)
      queries << sql
      raise StandardError, 'query refused' if fail_query && sql.to_s.match?(fail_query)

      key = sql ? query_results.keys.detect { |k| sql.include?(k) } : entities.last
      Struct.new(:entries).new(Array(query_results[key]))
    end

    # SyncServiceBase#sync: query_results[entity name] in pages
    def query_in_batches(sql, per_page: 1000)
      queries << sql
      Array(query_results[entities.last.to_s]).each_slice(per_page) { |batch| yield batch }
    end

    def find_by(field, value)
      records.values.select { |r| r.respond_to?(field) && r.public_send(field).to_s == value.to_s }
    end

    def all(sql)
      query(sql).entries
    end

    def pdf(doc)
      pdf_body || "PDF #{doc.id}"
    end
  end

  def install_fake_quickbooks(fake = FakeService.new)
    @restore_quickbooks ||= []
    [RedmineQboBilling::QboEstimateService, RedmineQboBilling::QboInvoiceService].each do |klass|
      replace_class_method(klass, :with_service) do |&block|
        fake.entities << klass.name.demodulize.gsub(/\AQbo|Service\z/, '')
        block.call(fake)
      end
    end
    replace_class_method(QboConnectionService, :with_qbo_service) do |entity: nil, &block|
      fake.entities << entity
      block.call(fake)
    end
    fake
  end

  def replace_class_method(klass, name, &body)
    original = klass.method(name)
    klass.define_singleton_method(name, &body)
    @restore_quickbooks << -> { klass.define_singleton_method(name, original) }
  end

  def self.included(base)
    base.teardown { Array(@restore_quickbooks).reverse_each(&:call) }
  end

  # The QuickBooks company's sales form settings (RedmineQboBilling::Company.settings)
  def stub_company(custom_fields: [{ id: 1, name: 'Sales Rep' }, { id: 2, name: 'VIN' }], custom_txn_numbers: false,
                   estimate_message: 'Thank you for your business', invoice_message: 'Payment due on receipt')
    RedmineQboBilling::Company.stubs(:settings).returns(
      custom_fields: custom_fields, custom_txn_numbers: custom_txn_numbers, allow_discount: true,
      estimate_message: estimate_message, invoice_message: invoice_message
    )
  end

  def stub_local_syncs
    EstimateSyncService.any_instance.stubs(:sync_by_id)
    InvoiceSyncService.any_instance.stubs(:sync_by_id)
    PaymentSyncService.any_instance.stubs(:sync_by_id)
  end

  # ---- QuickBooks documents ----

  def qbo_ref(value, name = nil)
    Quickbooks::Model::BaseReference.new(value.to_s, name: name)
  end

  def qbo_link(type, id)
    Quickbooks::Model::LinkedTransaction.new(txn_id: id.to_s, txn_type: type)
  end

  def qbo_sales_line(id, item_id, name, quantity, rate, taxable: true, description: '')
    line = Quickbooks::Model::InvoiceLineItem.new
    line.id = id.to_s
    line.description = description
    line.amount = (BigDecimal(quantity.to_s) * BigDecimal(rate.to_s)).round(2)
    line.sales_item! do |d|
      d.item_ref = qbo_ref(item_id, name)
      d.quantity = BigDecimal(quantity.to_s)
      d.unit_price = BigDecimal(rate.to_s)
      d.tax_code_ref = qbo_ref(taxable ? 'TAX' : 'NON')
    end
    line
  end

  def qbo_note_line(id, text)
    line = Quickbooks::Model::InvoiceLineItem.new
    line.id = id.to_s
    line.description = text
    line.description_only!
    line
  end

  def qbo_subtotal_line(id = nil)
    line = Quickbooks::Model::InvoiceLineItem.new
    line.id = id.to_s if id
    line.detail_type = 'SubTotalLineDetail'
    line
  end

  def qbo_discount_line(amount, percent: nil, account: nil)
    line = Quickbooks::Model::InvoiceLineItem.new
    line.amount = BigDecimal(amount.to_s)
    line.discount_item! do |d|
      d.percent_based = !percent.nil?
      d.discount_percent = BigDecimal(percent.to_s) if percent
      d.discount_account_ref = qbo_ref(account) if account
    end
    line
  end

  def qbo_custom_field(id, name, value)
    field = Quickbooks::Model::CustomField.new
    field.id = id
    field.name = name
    field.type = 'StringType'
    field.string_value = value
    field
  end

  def qbo_document(klass, id:, customer_id:, customer_name: nil, lines: [], status: nil, links: [], doc_number: nil,
                   total: nil, balance: nil, custom_fields: [], sync_token: 3, txn_date: Date.new(2026, 11, 10))
    doc = klass.new
    doc.id = id.to_s
    doc.sync_token = sync_token
    doc.doc_number = doc_number || id.to_s
    doc.txn_date = txn_date
    doc.customer_ref = qbo_ref(customer_id, customer_name)
    doc.line_items = lines
    doc.txn_status = status if doc.respond_to?(:txn_status=)
    doc.linked_transactions = links
    doc.total = BigDecimal(total.to_s) if total
    doc.balance = BigDecimal(balance.to_s) if balance && doc.respond_to?(:balance=)
    doc.custom_fields = custom_fields
    doc
  end

  def qbo_estimate(id: 598, customer_id: 9101, **options)
    qbo_document(Quickbooks::Model::Estimate, id: id, customer_id: customer_id, **options)
  end

  def qbo_invoice(id: 601, customer_id: 9101, **options)
    qbo_document(Quickbooks::Model::Invoice, id: id, customer_id: customer_id, **options)
  end

  def local_customer(id = 9101, name = 'Jane Customer')
    Customer.where(id: id).delete_all
    customer = Customer.new(id: id, name: name)
    customer.skip_qbo_push = true
    customer.save!
    customer
  end
end
