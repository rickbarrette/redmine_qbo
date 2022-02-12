#The License
#
#Copyright (c) 2022 Rick Barrette - All Rights Reserved
# 
#Unauthorized copying of this software and associated documentation files (the "Software"), via any medium is strictly prohibited.
#
#Proprietary and confidential
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class CreateLineItems < ActiveRecord::Migration[5.1]
  def change  
    create_table :line_items do |t| 
      t.integer  :item_id
      t.float    :amount
      t.string   :description 
      t.float    :unit_price 
      t.float    :quantity
      t.boolean  :billed
    end
    
    add_reference :line_items, :issues, index: true
  end
end
