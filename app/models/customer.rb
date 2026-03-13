#The MIT License (MIT)
#
#Copyright (c) 2016 - 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class Customer < QboBaseModel

  include Redmine::Acts::Searchable
  include Redmine::Acts::Event  

  has_many :issues
  has_many :invoices
  has_many :estimates
  validates_presence_of :name
  before_validation :normalize_phone_numbers
  self.primary_key = :id
  qbo_sync push: true
  
  acts_as_searchable columns: %w[name phone_number mobile_phone_number ],
                     scope: ->(_context) { left_joins(:project) },
                     date_column: :updated_at

  acts_as_event :title => Proc.new {|o| "#{o}"},
                :url => Proc.new {|o| { :controller => 'customers', :action => 'show', :id => o.id} },
                :type => :to_s,
                :description => Proc.new {|o| "#{I18n.t :label_primary_phone}: #{o.phone_number} #{I18n.t:label_mobile_phone}: #{o.mobile_phone_number}"},
                :datetime => Proc.new {|o| o.updated_at || o.created_at}

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
  
  # Customers are not bound by a project
  # but we need to implement this method for the Redmine::Acts::Searchable interface
  def project
    nil
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
  
  # returns a human readable string
  def to_s
    last4 = phone_number&.last(4)
    last4.present? ? "#{name} - #{last4}" : name.to_s
  end
  
end