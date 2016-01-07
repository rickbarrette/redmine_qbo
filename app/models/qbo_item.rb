class QboItem < ActiveRecord::Base
  unloadable
   attr_accessible :name
  
  def self.update_all 
    qbo = Qbo.first
    service = Quickbooks::Service::Item.new(:company_id => qbo.realmId, :access_token => Qbo.get_auth_token)
    
    # Update the item table
    service.all.each { |item|
      qbo_item = QboItem.find_or_create_by(id: item.id)
      qbo_item.name = item.name
      qbo_item.save!
    }
  end
end
