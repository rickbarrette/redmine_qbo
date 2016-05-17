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
  
  def self.sync 
    last = Qbo.first.last_sync
    
    query = "SELECT Id, Name FROM Item"
    query << "WHERE Type = 'Service'"
    #query << "AND Metadata.LastUpdatedTime > '#{last}'" if last
    
    items = get_base.service.query()    
    transaction do
      # Update the item table
      items.each { |item|
        qbo_item = QboItem.find_or_create_by(id: item.id)
        qbo_item.update_column(:name, item.name)
        qbo_item.update_column(:id, item.id)
      }
    end
    
    #remove deleted items
    where.not(items.map(&:id)).destroy_all
  end
end
