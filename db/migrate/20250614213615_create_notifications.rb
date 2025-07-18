class CreateNotifications < ActiveRecord::Migration[7.0]
  def change
    create_table :notifications do |t|
      t.references :recipient, null: false, foreign_key: { to_table: :users }
      t.references :task, null: false, foreign_key: true  # Still needed for quick reference
      t.references :review, foreign_key: true
      t.string :message, null: false
      t.boolean :read, default: false
      t.string :notification_type
      t.datetime :deleted_at  # Soft delete column

      t.timestamps
    end

    add_index :notifications, :deleted_at
  end
end
