class AddStableNodeIdToActionNodes < ActiveRecord::Migration[7.1]
  def up
    return if column_exists?(:action_nodes, :stable_node_id)

    add_column :action_nodes, :stable_node_id, :string
    return if index_exists?(:action_nodes, :stable_node_id, name: "index_action_nodes_on_stable_node_id")

    add_index :action_nodes, :stable_node_id, name: "index_action_nodes_on_stable_node_id"
  end

  def down
    if index_exists?(:action_nodes, :stable_node_id, name: "index_action_nodes_on_stable_node_id")
      remove_index :action_nodes, name: "index_action_nodes_on_stable_node_id"
    end
    remove_column :action_nodes, :stable_node_id if column_exists?(:action_nodes, :stable_node_id)
  end
end
