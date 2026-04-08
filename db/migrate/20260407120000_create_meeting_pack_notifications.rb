# frozen_string_literal: true

class CreateMeetingPackNotifications < ActiveRecord::Migration[7.1]
  def change
    create_table :meeting_pack_notifications do |t|
      t.references :user, null: false, foreign_key: true, index: true
      t.string :kind, null: false
      t.text :body, null: false
      t.datetime :read_at
      t.json :payload
      t.string :dedupe_key

      t.timestamps
    end

    add_index :meeting_pack_notifications, [:user_id, :kind]
    add_index :meeting_pack_notifications, [:user_id, :created_at], order: { created_at: :desc }
    add_index :meeting_pack_notifications, [:user_id, :dedupe_key], unique: true, where: "dedupe_key IS NOT NULL"
  end
end
