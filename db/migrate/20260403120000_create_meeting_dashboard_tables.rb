# frozen_string_literal: true

class CreateMeetingDashboardTables < ActiveRecord::Migration[7.1]
  def change
    create_table :new_tasks do |t|
      t.string :sector_division, null: false
      t.text :description, null: false
      t.datetime :original_date, null: false
      t.datetime :review_date, null: false
      t.string :responsibility, null: false
      t.datetime :completed_at
      t.integer :status, default: 0, null: false
      t.references :editor, null: true, foreign_key: { to_table: :users }
      t.references :reviewer, null: true, foreign_key: { to_table: :users }
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :new_tasks, :deleted_at
    add_index :new_tasks, :status

    create_table :new_action_nodes do |t|
      t.references :new_task, null: false, foreign_key: true
      t.bigint :parent_id
      t.text :content, size: :medium, null: false
      t.datetime :review_date
      t.integer :level, default: 1
      t.string :list_style, default: "decimal", null: false
      t.boolean :completed, default: false, null: false
      t.integer :position, null: false
      t.string :node_type, null: false
      t.references :reviewer, null: true, foreign_key: { to_table: :users }
      t.string :stable_node_id
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :new_action_nodes, :parent_id
    add_index :new_action_nodes, :deleted_at
    add_index :new_action_nodes, :stable_node_id
    add_index :new_action_nodes, [:new_task_id, :parent_id, :position], name: "index_new_action_nodes_on_task_parent_position"

    add_foreign_key :new_action_nodes, :new_action_nodes, column: :parent_id

    create_table :new_dashboard_versions do |t|
      t.date :target_meeting_date, null: false
      t.datetime :published_at, null: false
      t.references :published_by, null: false, foreign_key: { to_table: :users }
      t.string :note
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :new_dashboard_versions, :deleted_at
    add_index :new_dashboard_versions, [:target_meeting_date, :published_at], name: "index_new_dv_on_meeting_date_and_published_at"

    create_table :new_dashboard_snapshot_tasks do |t|
      t.references :new_dashboard_version, null: false, foreign_key: true
      t.bigint :source_new_task_id
      t.string :sector_division, null: false
      t.text :description, null: false
      t.datetime :original_date, null: false
      t.datetime :review_date, null: false
      t.string :responsibility, null: false
      t.datetime :completed_at
      t.integer :status, default: 0, null: false
      t.bigint :editor_id
      t.bigint :reviewer_id
      t.integer :display_position, default: 0, null: false
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :new_dashboard_snapshot_tasks, :source_new_task_id
    add_index :new_dashboard_snapshot_tasks, :deleted_at
    add_index :new_dashboard_snapshot_tasks, [:new_dashboard_version_id, :display_position],
              name: "index_new_dst_on_version_and_display_position"
    add_foreign_key :new_dashboard_snapshot_tasks, :new_tasks, column: :source_new_task_id, on_delete: :nullify
    add_foreign_key :new_dashboard_snapshot_tasks, :users, column: :editor_id
    add_foreign_key :new_dashboard_snapshot_tasks, :users, column: :reviewer_id

    create_table :new_dashboard_snapshot_action_nodes do |t|
      t.references :new_dashboard_version, null: false, foreign_key: true
      t.references :new_dashboard_snapshot_task, null: false, foreign_key: true
      t.bigint :parent_id
      t.bigint :source_new_action_node_id
      t.text :content, size: :medium, null: false
      t.datetime :review_date
      t.integer :level, default: 1
      t.string :list_style, default: "decimal", null: false
      t.boolean :completed, default: false, null: false
      t.integer :position, null: false
      t.string :node_type, null: false
      t.bigint :reviewer_id
      t.string :stable_node_id
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :new_dashboard_snapshot_action_nodes, :parent_id
    add_index :new_dashboard_snapshot_action_nodes, :source_new_action_node_id
    add_index :new_dashboard_snapshot_action_nodes, :deleted_at
    add_index :new_dashboard_snapshot_action_nodes, :stable_node_id
    add_index :new_dashboard_snapshot_action_nodes,
              [:new_dashboard_snapshot_task_id, :parent_id, :position],
              name: "index_new_dsan_on_snapshot_task_parent_position"

    add_foreign_key :new_dashboard_snapshot_action_nodes, :new_dashboard_snapshot_action_nodes, column: :parent_id
    add_foreign_key :new_dashboard_snapshot_action_nodes, :new_action_nodes, column: :source_new_action_node_id, on_delete: :nullify
    add_foreign_key :new_dashboard_snapshot_action_nodes, :users, column: :reviewer_id

    create_table :new_meeting_schedules do |t|
      t.date :meeting_date, null: false
      t.references :current_new_dashboard_version, null: false, foreign_key: { to_table: :new_dashboard_versions }
      t.references :set_by_user, null: false, foreign_key: { to_table: :users }
      t.datetime :set_at, null: false
      t.text :reason
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :new_meeting_schedules, :meeting_date
    add_index :new_meeting_schedules, :deleted_at

    create_table :new_meeting_schedule_events do |t|
      t.string :event_type, null: false
      t.date :from_meeting_date
      t.date :to_meeting_date
      t.references :new_dashboard_version, null: true, foreign_key: true
      t.references :new_meeting_schedule, null: true, foreign_key: true
      t.references :actor, null: false, foreign_key: { to_table: :users }
      t.json :payload
      t.timestamps
    end
    add_index :new_meeting_schedule_events, :event_type
    add_index :new_meeting_schedule_events, :created_at

    create_table :new_dashboard_assignments do |t|
      t.references :new_dashboard_version, null: false, foreign_key: true
      t.references :new_dashboard_snapshot_action_node, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :new_dashboard_assignments, :deleted_at
    add_index :new_dashboard_assignments,
              [:new_dashboard_version_id, :new_dashboard_snapshot_action_node_id, :user_id],
              name: "index_new_da_on_version_node_user"

    create_table :new_dashboard_node_comments do |t|
      t.references :new_dashboard_version, null: false, foreign_key: true
      t.references :new_dashboard_snapshot_action_node, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.text :body, null: false
      t.datetime :deleted_at
      t.timestamps
    end
    add_index :new_dashboard_node_comments, :deleted_at

    create_table :new_dashboard_draft_settings do |t|
      t.string :singleton_key, null: false, default: "global"
      t.date :target_meeting_date
      t.references :updated_by, null: true, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :new_dashboard_draft_settings, :singleton_key, unique: true
  end
end
