class BackfillActionNodesStableId < ActiveRecord::Migration[7.1]
  def up
    ActionNode.unscoped.where(stable_node_id: nil).find_each do |node|
      node.update_column(:stable_node_id, SecureRandom.uuid)
    end
  end

  def down
    # Not removing existing stable_node_ids on rollback
  end
end
