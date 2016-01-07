class CreateQboEmployees < ActiveRecord::Migration
  def change
    create_table :qbo_employees do |t|
      t.string :name
    end
  end
end
