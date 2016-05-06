#The MIT License (MIT)
#
#Copyright (c) 2016 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class Vehicle < ActiveRecord::Base
  
  unloadable
  belongs_to :customer
  
  attr_accessible :year, :make, :model, :customer_id, :notes, :vin
  validates_presence_of :customer_id
  validates :vin, uniqueness: true
  
  validate :decode_vin
  after_initialize :get_details
  
  # returns a human readable string
  def to_s
    return "#{self.year} #{self.make} #{self.model}"
  end
  
  # returns the raw JSON details from EMUNDS
  def details
    return @details
  end
  
  # returns the style of the vehicle
  def style
    begin
      return @details['years'][0]['styles'][0]['name'] if @details
    rescue
      return nil
    end
  end
  
  # returns the drive of the vehicle i.e. 2 wheel, 4 wheel, ect.
  def drive
    return @details['drivenWheels'] if @details
  end
  
  # returns the number of doors of the vehicle
  def doors
    return @details['numOfDoors'] if @details
  end
  
  private
  
  # init method to pull JSON details from Edmunds
  def get_details
    # TODO handle ERRORS
    if self.vin?
      begin
        @details = JSON.parse get_decoder.full(self.vin)
      rescue Exception => e
        errors.add(:vin, e.message)
      end
    end
  end
  
  # returns the Edmunds decoder service
  def get_decoder
    #TODO API Code via Settings
    return decoder = Edmunds::Vin.new('2dheutzvhxs28dzukx5tgu47')
  end
  
  # decodes a vin and updates self
  def decode_vin
    get_details
    if @details and self.vin?
      begin
        self.year = @details['years'][0]['year']
      rescue
      end
      
      begin
        self.make = @details['make']['name']
      rescue
      end
    
      begin
        self.model = @details['model']['name']
      rescue
      end
    end
    self.name = to_s
  end
  
  # makes a squishvin
  # https://api.edmunds.com/api/vehicle/v2/squishvins/#{vin}/?fmt=json&api_key=#{ENV['edmunds_key']}
  def vin_squish
    if not self.vin? or self.vin.size < 11
      # this is to go ahead and query the API, letting them handle the error. :P
      return '1000000000A'
    end
    v = self.vin[0,11]
    return v.slice(0,8) + v.slice(9,11)
  end
end
