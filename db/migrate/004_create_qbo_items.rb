class CreateQboItems < ActiveRecord::Migration
  def change
    create_table :qbo_items do |t|
      t.string :name
    end
  end
end
