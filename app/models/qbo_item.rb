#The MIT License (MIT)
#
#Copyright (c) 2016 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class QboItem < ActiveRecord::Base
  unloadable
  has_many :issues
  attr_accessible :name
  validates_presence_of :id, :name
  
  def self.get_base
    Qbo.get_base(:item)
  end
  
  def self.update_all 
    service = get_base.service
        
    # Update the item table
    service.find_by(:type, "Service").each { |item|
      qbo_item = QboItem.find_or_create_by(id: item.id)
      qbo_item.name = item.name
      qbo_item.id = item.id
      qbo_item.save!
    }
    
    #remove deleted items
    all.each { |item|
      begin
        service.fetch_by_id(item.id)
      rescue
        delete_all(id: item.id)
      end
    }
  end
end
