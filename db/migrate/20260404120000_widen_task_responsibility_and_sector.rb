# frozen_string_literal: true

# HTML imports can carry very long "Responsibility" / sector lines (many roles, commas).
# Default VARCHAR(255) caused Mysql2::Error: Data too long for column 'responsibility'.
class WidenTaskResponsibilityAndSector < ActiveRecord::Migration[7.1]
  def up
    change_column :new_tasks, :sector_division, :mediumtext, null: false
    change_column :new_tasks, :description, :mediumtext, null: false
    change_column :new_tasks, :responsibility, :mediumtext, null: false

    change_column :new_dashboard_snapshot_tasks, :sector_division, :mediumtext, null: false
    change_column :new_dashboard_snapshot_tasks, :description, :mediumtext, null: false
    change_column :new_dashboard_snapshot_tasks, :responsibility, :mediumtext, null: false

    change_column :tasks, :sector_division, :mediumtext, null: false
    change_column :tasks, :description, :mediumtext, null: false
    change_column :tasks, :responsibility, :mediumtext, null: false

    # Headroom for huge single-node HTML (MEDIUMTEXT → LONGTEXT).
    change_column :new_action_nodes, :content, :longtext, null: false
    change_column :new_dashboard_snapshot_action_nodes, :content, :longtext, null: false
  end

  def down
    # May truncate rows if rolled back.
    change_column :new_tasks, :sector_division, :string, null: false
    change_column :new_tasks, :description, :text, null: false
    change_column :new_tasks, :responsibility, :string, null: false

    change_column :new_dashboard_snapshot_tasks, :sector_division, :string, null: false
    change_column :new_dashboard_snapshot_tasks, :description, :text, null: false
    change_column :new_dashboard_snapshot_tasks, :responsibility, :string, null: false

    change_column :tasks, :sector_division, :string, null: false
    change_column :tasks, :description, :text, null: false
    change_column :tasks, :responsibility, :string, null: false

    change_column :new_action_nodes, :content, :mediumtext, null: false
    change_column :new_dashboard_snapshot_action_nodes, :content, :mediumtext, null: false
  end
end
