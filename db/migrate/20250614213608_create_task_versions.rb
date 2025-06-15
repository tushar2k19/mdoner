class CreateTaskVersions < ActiveRecord::Migration[7.0]
  def change
    create_table :task_versions do |t|
      t.references :task, null: false, foreign_key: true  # Parent task
      t.references :editor, foreign_key: { to_table: :users }  # User who created this version
      t.references :base_version, foreign_key: { to_table: :task_versions }  # Previous approved version (for diffing)
      t.integer :version_number, null: false  # Sequential version number
      t.string :status, null: false, default: 'draft'  # draft/under_review/approved/completed
      t.text :change_description  # Summary of changes in this version

      t.timestamps
    end

    # Adds reference to current approved version on tasks table
    add_column :tasks, :current_version_id, :bigint
    add_foreign_key :tasks, :task_versions, column: :current_version_id
  end
end
