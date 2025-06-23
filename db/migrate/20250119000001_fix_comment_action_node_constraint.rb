class FixCommentActionNodeConstraint < ActiveRecord::Migration[7.1]
  def up
    # Remove the existing foreign key constraint
    remove_foreign_key :comments, :action_nodes
    
    # Add new foreign key constraint with ON DELETE SET NULL
    add_foreign_key :comments, :action_nodes, on_delete: :nullify
  end

  def down
    # Remove the modified constraint
    remove_foreign_key :comments, :action_nodes
    
    # Restore the original constraint
    add_foreign_key :comments, :action_nodes
  end
end 