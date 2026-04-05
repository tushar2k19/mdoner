# frozen_string_literal: true

class NewDashboardVersion < ApplicationRecord
  acts_as_paranoid

  belongs_to :published_by, class_name: "User"
  has_many :new_dashboard_snapshot_tasks, dependent: :destroy
  has_many :new_dashboard_snapshot_action_nodes, dependent: :destroy
  has_many :new_meeting_schedules, foreign_key: :current_new_dashboard_version_id,
                                   inverse_of: :current_new_dashboard_version
  has_many :new_dashboard_assignments, dependent: :destroy
  has_many :new_dashboard_node_comments, dependent: :destroy
  has_many :new_dashboard_pack_node_resolutions, dependent: :destroy

  validates :target_meeting_date, :published_at, presence: true
end
