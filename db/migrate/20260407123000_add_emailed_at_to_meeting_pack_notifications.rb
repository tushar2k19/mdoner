# frozen_string_literal: true

class AddEmailedAtToMeetingPackNotifications < ActiveRecord::Migration[7.1]
  def change
    add_column :meeting_pack_notifications, :emailed_at, :datetime
  end
end
