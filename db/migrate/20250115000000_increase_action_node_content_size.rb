class IncreaseActionNodeContentSize < ActiveRecord::Migration[7.1]
  def up
    # Change content column from TEXT to MEDIUMTEXT to support larger content
    # MEDIUMTEXT can hold up to 16MB of data
    change_column :action_nodes, :content, :mediumtext, null: false
    
  end

  def down
    # Revert back to TEXT type
    change_column :action_nodes, :content, :text, null: false
  end
end 