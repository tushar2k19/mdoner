# frozen_string_literal: true

class CreateNewDashboardPackNodeResolutions < ActiveRecord::Migration[7.1]
  def change
    create_table :new_dashboard_pack_node_resolutions do |t|
      t.references :new_dashboard_version, null: false, foreign_key: true
      t.references :new_dashboard_snapshot_action_node, null: false, foreign_key: true
      t.boolean :resolved, null: false, default: false
      t.datetime :resolved_at
      t.references :resolved_by, foreign_key: { to_table: :users }

      t.datetime :deleted_at
      t.timestamps
    end

    add_index :new_dashboard_pack_node_resolutions, :deleted_at
    add_index :new_dashboard_pack_node_resolutions,
              %i[new_dashboard_version_id new_dashboard_snapshot_action_node_id],
              unique: true,
              name: "idx_pack_resolutions_version_and_snapshot_node"
  end
end
