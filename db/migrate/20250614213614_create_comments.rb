class CreateComments < ActiveRecord::Migration[7.0]
  def change
    create_table :comments do |t|
      t.text :content, null: false
      t.datetime :review_date, null: false
      t.references :user, null: false, foreign_key: true
      t.references :comment_trail, null: false, foreign_key: true  # New association
      t.references :action_node, foreign_key: true  # Links to specific nodes
      t.boolean :resolved, default: false  # Tracks comment resolution
      t.datetime :deleted_at  # Soft delete column

      t.timestamps
    end

    add_index :comments, :deleted_at
    # Removed task_id reference (now through comment_trail → review → task_version → task)
  end
end
