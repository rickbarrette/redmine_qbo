#The MIT License (MIT)
#
#Copyright (c) 2024 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class Vehicle < ActiveRecord::Base
  
  belongs_to :customer
  has_many :issues, :foreign_key => 'vehicles_id'
  
  validates_presence_of :customer
  validates :vin, uniqueness: true
  before_save :decode_vin
  
  self.primary_key = :id
  
  # returns a human readable string
  def to_s
    if year.nil? or make.nil? or model.nil?
      return "#{vin}"
    else
      split_vin = vin.scan(/.{1,9}/)
      return "#{year} #{make} #{model} - #{split_vin[1]}"
    end
  end
  
  # returns the raw JSON details from NHTSA
  def details
    get_details if @details.nil?
    return @details
  end
  
  # Force Upper Case for make numbers
  def make=(val)
    # The to_s is in case you get nil/non-string
    write_attribute(:make, val.to_s.titleize)
  end
  
  # Force Upper Case for model numbers
  def model=(val)
    # The to_s is in case you get nil/non-string
    write_attribute(:model, val.to_s.titleize)
  end
  
  # Force Upper Case & strip VIN of all illegal chars (for barcode scanner)
  def vin=(val)
    val = val.to_s.upcase.gsub(/[^A-HJ-NPR-Za-hj-npr-z\d]+/,"")
    write_attribute(:vin, val)
  end
  
  # search for a vin
  def self.search(search)
    where("vin LIKE ?", "%#{search}%")
  end
	
  # decodes a vin and updates self
  def decode_vin
    get_details
    if @details
      begin
        self.year = @details.year unless @details.year.nil?
        self.make = @details.make unless @details.make.nil?
        self.model = @details.model unless @details.model.nil?
        self.doors = @details.doors unless @details.doors.nil?
        self.trim = @details.trim unless @details.trim.nil?
      rescue Exception => e
        errors.add(:vin, e.message)
      end
    end
    self.name = to_s
  end
  
  private
  
  # init method to pull JSON details from NHTSA
  def get_details
    if self.vin?
      #validate the vin before calling a remote server
      validation = NhtsaVin.validate(self.vin)
      begin
        #if the vin validation failed, raise an exception and exit
        raise RuntimeError, validation.error unless validation.valid?
        # query NHTSA for details on the vin
        query = NhtsaVin.get(self.vin)
        raise RuntimeError, query.error unless query.valid?
        @details = query.response
      rescue Exception => e
        errors.add(:vin, e.message)
      end
    end
  end
  
end
