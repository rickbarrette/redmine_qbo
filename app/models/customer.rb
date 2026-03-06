#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class Customer < ActiveRecord::Base

  include Redmine::Acts::Searchable
  include Redmine::Acts::Event  
  include Redmine::I18n

  has_many :issues
  has_many :invoices
  has_many :estimates
 
  validates_presence_of :id, :name
  before_validation :normalize_phone_numbers
  
  self.primary_key = :id

  acts_as_searchable columns: %w[name phone_number mobile_phone_number ],
                     scope: ->(_context) { left_joins(:project) },
                     date_column: :updated_at

  acts_as_event :title => Proc.new {|o| "#{o}"},
                :url => Proc.new {|o| { :controller => 'customers', :action => 'show', :id => o.id} },
                :type => :to_s,
                :description => Proc.new {|o| "#{I18n.t :label_primary_phone}: #{o.phone_number} #{I18n.t:label_mobile_phone}: #{o.mobile_phone_number}"},
                :datetime => Proc.new {|o| o.updated_at || o.created_at}

  # Returns the details of the customer. If the details have already been fetched, it returns the cached version. Otherwise, it fetches the details from QuickBooks Online and caches them for future use. This method is used to access the customer's information in a way that minimizes unnecessary API calls to QBO, improving performance and reducing latency.
  def details
    return (@details ||= Quickbooks::Model::Customer.new) if new_record?

    @details ||= begin
      xml = Rails.cache.fetch(details_cache_key, expires_in: 10.minutes) do
        fetch_details.to_xml_ns
      end

      Quickbooks::Model::Customer.from_xml(xml)
    end
  end

  # Generates a unique cache key for storing this customer's QBO details.
  def details_cache_key
    "customer:#{id}:qbo_details:#{updated_at.to_i}"
  end

  # Returns the customer's email address
  def email
    details
    return @details&.email_address&.address
  end
  
  # Updates the customer's email address
  def email=(s)
    details
    @details.email_address = s
  end
  

  # Returns the last sync time formatted for display. If no sync has occurred, returns a default message.
  def self.last_sync
    return I18n.t(:label_qbo_never_synced) unless maximum(:updated_at)
    format_time(maximum(:updated_at))
  end
  
  # Customers are not bound by a project
  # but we need to implement this method for the Redmine::Acts::Searchable interface
  def project
    nil
  end

  # Magic Method
  # Maps Get/Set methods to QBO customer object
  def method_missing(method_name, *args, &block)
    if Quickbooks::Model::Customer.method_defined?(method_name)
      details
      @details.public_send(method_name, *args, &block)
    else
      super
    end
  end

  # returns the customer's mobile phone
  def mobile_phone
    details
    return @details&.mobile_phone&.free_form_number
  end
  
  # Updates the custome's mobile phone number
  def mobile_phone=(n)
    details
    pn = Quickbooks::Model::TelephoneNumber.new
    pn.free_form_number = n
    @details.mobile_phone = pn
  end

  # Updates Both local DB name & QBO display_name
  def name=(s)
    details
    @details.display_name = s
    super
  end

  # Normalizes phone numbers by removing non-digit characters. This method is called before validation to ensure that phone numbers are stored in a consistent format, which can help with searching and integration with external systems like QuickBooks Online.
  def normalize_phone_numbers
    self.phone_number = phone_number.to_s.gsub(/\D/, '') if phone_number.present?
    self.mobile_phone_number = mobile_phone_number.to_s.gsub(/\D/, '') if mobile_phone_number.present?
  end

  # Sets the notes for the customer
  def notes=(s)
    details
    @details.notes = s
  end

  # returns the customer's primary phone
  def primary_phone
    details
    return @details&.primary_phone&.free_form_number
  end
  
  # Updates the customer's primary phone number
  def primary_phone=(n)
    details
    pn = Quickbooks::Model::TelephoneNumber.new
    pn.free_form_number = n
    @details.primary_phone = pn
  end

  # Repsonds to missing methods by delegating to the QBO customer details object if the method is defined there. This allows for dynamic access to any attributes or methods of the QBO customer without having to explicitly define them in the Customer model, providing flexibility and reducing boilerplate code.
  def respond_to_missing?(method_name, include_private = false)
    Quickbooks::Model::Customer.method_defined?(method_name) || super
  end

  # Seach for customers by name or phone number
  def self.search(search)
    #return none if search.blank?
    search = sanitize_sql_like(search)
    where("name LIKE ? OR phone_number LIKE ? OR mobile_phone_number LIKE ?", "%#{search}%", "%#{search}%", "%#{search}%")
  end

  # Override the defult redmine seach method to rank results by id
  def self.search_result_ranks_and_ids(tokens, user, project = nil, options = {})
    return {} if tokens.blank?

    scope = self.all

    tokens.each do |token|
      scope = scope.search(token)
    end

    ids = scope.distinct.limit(options[:limit] || 100).pluck(:id)
    ids.index_with { |id| id }
  end
  
  # performs a sync operation for all customers
  def self.sync 
    CustomerSyncJob.perform_later(full_sync: false)
  end

  # performs a sync operation for a specific customer
  def self.sync_by_id(id) 
    CustomerSyncJob.perform_later(id: id)
  end
  
  # returns a human readable string
  def to_s
    last4 = phone_number&.last(4)
    last4.present? ? "#{name} - #{last4}" : name.to_s
  end

  # Push the updates
  def save_with_push
    log "Starting push for customer ##{self.id}..."
    qbo = QboConnectionService.current!
    CustomerService.new(qbo: qbo, customer: self).push()
    Rails.cache.delete(details_cache_key)
    save_without_push
  end

  alias_method :save_without_push, :save
  alias_method :save, :save_with_push
  
  private

  # Fetches the customer's details from QuickBooks Online. If the customer has an ID, it makes an authenticated request to QBO to retrieve the customer's information. If the customer does not have an ID or if there is an error during the fetch, it returns a new instance of Quickbooks::Model::Customer with default values. This method is used to ensure that the customer object has the most up-to-date information from QBO when needed.
  def fetch_details
    return Quickbooks::Model::Customer.new unless id.present?
    log "Fetching details for customer ##{id} from QBO..."
    qbo = QboConnectionService.current!
    CustomerService.new(qbo: qbo, customer: self).pull()
  end

  # Log messages with the entity type for better traceability
  def log(msg)
    Rails.logger.info "[Customer] #{msg}"
  end
  
end
