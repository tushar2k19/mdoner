class AddNewTaskIdToNotifications < ActiveRecord::Migration[7.1]
  def change
    add_column :notifications, :new_task_id, :bigint
    add_index :notifications, :new_task_id
    add_foreign_key :notifications, :new_tasks
    
    change_column_null :notifications, :task_id, true
  end
end
