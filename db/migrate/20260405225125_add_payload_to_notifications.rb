class AddPayloadToNotifications < ActiveRecord::Migration[7.1]
  def change
    add_column :notifications, :payload, :json
  end
end
