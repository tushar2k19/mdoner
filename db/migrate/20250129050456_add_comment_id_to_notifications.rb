class AddCommentIdToNotifications < ActiveRecord::Migration[7.0]
  def change
    add_column :notifications, :comment_id, :integer
    add_index :notifications, :comment_id
  end
end
