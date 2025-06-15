# db/migrate/[timestamp]_create_tasks.rb
class CreateTasks < ActiveRecord::Migration[7.0]
  def change
    create_table :tasks do |t|
      t.string :sector_division, null: false
      t.text :description, null: false
      t.datetime :original_date, null: false
      t.string :responsibility, null: false
      t.datetime :review_date, null: false
      t.datetime :completed_at
      t.integer :status, default: 0
      t.references :editor, foreign_key: { to_table: :users }
      t.references :reviewer, foreign_key: { to_table: :users }, null: true
      t.datetime :deleted_at  # Soft delete column
      t.references :current_version, foreign_key: { to_table: :task_versions }  # Current approved version

      t.timestamps
    end

    add_index :tasks, :deleted_at  # For soft delete queries
    # Removed action_to_be_taken column completely
  end
end
