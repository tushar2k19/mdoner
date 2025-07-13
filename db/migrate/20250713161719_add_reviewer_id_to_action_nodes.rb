class AddReviewerIdToActionNodes < ActiveRecord::Migration[7.1]
  def change
    add_reference :action_nodes, :reviewer, null: true, foreign_key: { to_table: :users }
  end
end
