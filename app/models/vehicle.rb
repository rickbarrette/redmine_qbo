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
  belongs_to :qbo_customer
  
  attr_accessible :year, :make, :model, :qbo_customer_id, :notes, :vin
  validates_presence_of :year, :make, :model, :qbo_customer_id
  
  before_validation :decode_vin
  after_initialize :get_details
  
  def to_s
    return "#{self.year} #{self.make} #{self.model}"
  end
  
  def details
    return @details
  end
  
  private
  
  def get_details
    if not self.vin?
      @details = JSON.parse get_decoder.full(self.vin)
  end
  
  def get_decoder
    #TODO API Code via Settings
    return decoder = Edmunds::Vin.new('2dheutzvhxs28dzukx5tgu47')
  end
  
  def decode_vin
    if self.vin?
      details
      self.year = @details['years'][0]['year']
      self.make = @details['make']['name']
      self.model = @details['model']['name']
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
