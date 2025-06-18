class AddCurrentVersionToTasks < ActiveRecord::Migration[7.0]
  def change
    add_column :tasks, :current_version_id, :bigint
    add_foreign_key :tasks, :task_versions, column: :current_version_id
    add_index :tasks, :current_version_id
  end
end 