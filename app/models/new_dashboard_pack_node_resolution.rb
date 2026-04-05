# frozen_string_literal: true

# Editor acknowledgment per published pack node. Normal resolve/unresolve updates columns only;
# do not destroy rows (paranoid + unique index on version + snapshot node).
class NewDashboardPackNodeResolution < ApplicationRecord
  acts_as_paranoid

  belongs_to :new_dashboard_version
  belongs_to :new_dashboard_snapshot_action_node
  belongs_to :resolved_by, class_name: "User", optional: true

  validates :new_dashboard_version_id, presence: true
  validates :new_dashboard_snapshot_action_node_id, presence: true
  validates :new_dashboard_snapshot_action_node_id,
            uniqueness: { scope: :new_dashboard_version_id }
end
