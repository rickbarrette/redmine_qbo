class QboEmployee < ActiveRecord::Base
  unloadable
   attr_accessible :name
  
  def self.update_all 
    qbo = Qbo.first
    service = Quickbooks::Service::Employee.new(:company_id => qbo.realmId, :access_token => Qbo.get_auth_token)
    
    # Update the item table
    service.all.each { |employee|
      qbo_employee = QboEmployee.find_or_create_by(id: employee.id)
      qbo_employee.name = employee.display_name 
      qbo_employee.save!
    }
  end
  
end
