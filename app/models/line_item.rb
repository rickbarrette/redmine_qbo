#Copyright (c) 2018 Rick Barrette - All Rights Reserved
# 
#Unauthorized copying of this software and associated documentation files (the "Software"), via any medium is strictly prohibited.
#
#Proprietary and confidential
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class LineItem < ActiveRecord::Base
  
  unloadable
  
  belongs_to :issue
  
  attr_accessible :amount, :description, :unit_price, :quantity, :item_id
  validates_presence_of :amount, :description, :unit_price, :quantity
  
  def add_to_invoice(invoice)
    line_item = Quickbooks::Model::InvoiceLineItem.new
    line_item.amount = amount
    line_item.description = description
    line_item.sales_item! do |detail|
      detail.unit_price = unit_price
      detail.quantity = quantity
      detail.item_id = item_id # Item ID here... Where do i get this???
    end
    
    invoice.line_items << line_item
    
    return invoice
  end
end
