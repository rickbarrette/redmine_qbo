class 21AddQboInvoicesIssues < ActiveRecord::Migration
  def self.up
    create_table :qbo_invoices_issues, :id => false do |t|
      t.integer :qbo_invoice_id
      t.integer :issue_id
    end
  end

  def self.down
    drop_table :qbo_invoices_issues
  end
end
