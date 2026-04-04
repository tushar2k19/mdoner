# frozen_string_literal: true

class AddPublishedTagIdsToNewDashboardSnapshotTasks < ActiveRecord::Migration[7.1]
  def change
    add_column :new_dashboard_snapshot_tasks, :published_tag_ids, :json, null: true
  end
end
