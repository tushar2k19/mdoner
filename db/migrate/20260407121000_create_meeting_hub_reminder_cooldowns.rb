# frozen_string_literal: true

class CreateMeetingHubReminderCooldowns < ActiveRecord::Migration[7.1]
  def change
    create_table :meeting_hub_reminder_cooldowns do |t|
      t.references :editor, null: false, foreign_key: { to_table: :users }
      t.bigint :new_dashboard_version_id, null: false
      t.string :stable_node_id, null: false
      t.datetime :sent_at, null: false

      t.timestamps
    end

    add_index :meeting_hub_reminder_cooldowns,
              [:editor_id, :new_dashboard_version_id, :stable_node_id],
              unique: true,
              name: "index_meeting_hub_reminder_cooldowns_unique"
    add_foreign_key :meeting_hub_reminder_cooldowns, :new_dashboard_versions
  end
end
