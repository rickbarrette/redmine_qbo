#The MIT License (MIT)
#
#Copyright (c) 2026 rick barrette
#
#Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
#
#The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
#
#THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

# Billing in Redmine: writing, editing and emailing QuickBooks estimates and invoices, receiving payments,
# the QuickBooks product/service list and accounts, and creating issues from estimates. Called from
# RedmineQbo.setup. (It began as the separate redmine_qbo_billing plugin, hence the name; other plugins use
# its hooks and RedmineQboBilling::EstimateWriter.create_estimate.)
module RedmineQboBilling
  def self.setup
    # Invoice lines that bill time activities need a LinkedTxn
    RedmineQboBilling::Patches::InvoiceLineItemLinkedTxn.apply!

    # Hooks
    RedmineQboBilling::Hooks::QboHookListener

    # Administration menu: the QuickBooks product/service list (accounts are reached from it)
    Redmine::MenuManager.map :admin_menu do |menu|
      menu.push :redmine_qbo_items, { controller: 'items', action: 'index' }, icon: 'list', caption: :label_items,
                html: { class: 'icon icon-list' } unless menu.exists?(:redmine_qbo_items)
    end
  end

  # VINs to suggest in the estimate/invoice VIN box for a customer, from plugins answering
  #   :qbo_billing_vin_options, { customer: } => [{ vin:, name: }, ...] (e.g. redmine_qbo_vehicles: the
  #   customer's vehicles)
  def self.vin_options(customer)
    return [] unless customer

    Redmine::Hook.call_hook(:qbo_billing_vin_options, { customer: customer }).flatten.compact.filter_map do |option|
      option = option.to_h.symbolize_keys
      vin = option[:vin].to_s.strip
      { vin: vin, name: option[:name].to_s.presence || vin } unless vin.empty?
    end.uniq { |o| o[:vin].upcase }
  rescue StandardError => e
    Rails.logger.warn "[RedmineQboBilling] VIN suggestions failed: #{e.message}"
    []
  end

  # The VIN a new estimate or invoice starts with, from plugins answering
  #   :qbo_billing_default_vin, { customer:, issues: } => a VIN or nil (e.g. redmine_qbo_vehicles: the work
  #   orders' vehicle when they share one, else the customer's only vehicle)
  # issues are the work orders behind the document (e.g. the issues linked to the estimate it's made from).
  def self.default_vin(customer, issues: [])
    return nil unless customer

    Redmine::Hook.call_hook(:qbo_billing_default_vin, { customer: customer, issues: Array(issues) })
                 .flatten.compact.map { |vin| vin.to_s.strip }.reject(&:empty?).first
  rescue StandardError => e
    Rails.logger.warn "[RedmineQboBilling] Default VIN failed: #{e.message}"
    nil
  end

  # True when the user may write estimates
  def self.writer?(user = User.current)
    user.allowed_to?(:write_estimates, nil, global: true)
  end

  # True when the user may email estimates to customers
  def self.sender?(user = User.current)
    user.allowed_to?(:send_estimates, nil, global: true)
  end

  # True when the user may receive customer payments
  def self.payment_receiver?(user = User.current)
    user.allowed_to?(:receive_payments, nil, global: true)
  end

  # True when the user may see customer payments (receiving them includes seeing them)
  def self.payment_viewer?(user = User.current)
    user.allowed_to?(:view_payments, nil, global: true) || payment_receiver?(user)
  end

  # True when the user may write invoices
  def self.invoice_writer?(user = User.current)
    user.allowed_to?(:write_invoices, nil, global: true)
  end

  # True when the user may email invoices to customers
  def self.invoice_sender?(user = User.current)
    user.allowed_to?(:send_invoices, nil, global: true)
  end
end
