class CreateActionNodes < ActiveRecord::Migration[7.0]
  def change
    create_table :action_nodes do |t|
      t.references :task_version, null: false, foreign_key: true  # Links to the version this node belongs to
      t.references :parent, foreign_key: { to_table: :action_nodes }  # Parent node for hierarchical structure
      t.text :content, null: false  # Actual content of the node (text)
      t.datetime :review_date  # Optional date for when this item should be reviewed
      add_column :action_nodes, :level, :integer, default: 1
      add_column :action_nodes, :list_style, :string, default: 'decimal' 
      # list_style options: 'decimal', 'lower-alpha', 'lower-roman', 'bullet'
      t.boolean :completed, default: false  # Marks if the item has been discussed/completed
      t.integer :position, null: false  # Order position within its parent
      t.string :node_type, null: false  # Type: paragraph/point/subpoint/subsubpoint
      t.datetime :deleted_at  # For soft deletion


      t.timestamps
    end

    add_index :action_nodes, :deleted_at  # Index for soft delete queries
  end
end
