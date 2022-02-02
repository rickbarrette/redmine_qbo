#The MIT License (MIT)
#
#Copyright (c) 2022 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class QboItem < ActiveRecord::Base
  unloadable
  has_many :issues
  #attr_accessible :name
  validates_presence_of :id, :name

  self.primary_key = :id

  def self.get_base
    Qbo.get_base(:item)
  end
  
  def self.sync 
    last = Qbo.first.last_sync

    query = "SELECT Id, Name FROM Item WHERE Type = 'Service' "
    query << " AND  Metadata.LastUpdatedTime >= '#{last.iso8601}' " if last 
   
    if count == 0
      items = get_base.all
    else
      items = get_base.query(query)
    end

    unless items.count = 0
      items.find_by(:type, "Service").each { |i|
        qbo_item = QboItem.find_or_create_by(id: i.id)
        qbo_item.name = i.name
        qbo_item.id = i.id
        qbo_item.save
      }
    end
      
#    QboItem.where.not(items.map(&:id)).destroy_all
  end
  
end
