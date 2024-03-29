#The MIT License (MIT)
#
#Copyright (c) 2023 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

class UpdateQboToken < ActiveRecord::Migration[5.1]
  def change
    add_column :qbos, :oauth2_access_token, :text
    add_column :qbos, :oauth2_access_token_expires_at, :datetime
    add_column :qbos, :oauth2_refresh_token, :text
    add_column :qbos, :oauth2_refresh_token_expires_at, :datetime
    add_column :qbos, :realm_id, :text
    remove_column :qbos, :company_id
    remove_column :qbos, :token
    remove_column :qbos, :expire
  end
end
