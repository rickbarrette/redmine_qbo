class CreateCustomerTokens < ActiveRecord::Migration
  def change
    create_table :customer_tokens do |t|

      t.string :token

      t.timestamp :expires_at


    end

  end
end
