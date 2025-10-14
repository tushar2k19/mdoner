class CreateTaskTags < ActiveRecord::Migration[7.1]
  def change
    create_table :task_tags, if_not_exists: true do |t|
      t.references :task, null: false, foreign_key: true
      t.references :tag, null: false, foreign_key: true
      t.references :created_by, null: true, foreign_key: { to_table: :users }
      t.timestamps
    end

    # Prevent duplicate tag on the same task
    add_index :task_tags, [:task_id, :tag_id], unique: true, if_not_exists: true
    # Speed up filtering by tag
    add_index :task_tags, :tag_id, if_not_exists: true
  end
end