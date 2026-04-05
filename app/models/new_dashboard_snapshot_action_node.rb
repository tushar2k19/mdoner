# frozen_string_literal: true

class NewDashboardSnapshotActionNode < ApplicationRecord
  include NewFlowNodeHtml

  acts_as_paranoid

  belongs_to :new_dashboard_version
  belongs_to :new_dashboard_snapshot_task, inverse_of: :new_dashboard_snapshot_action_nodes
  belongs_to :parent, class_name: "NewDashboardSnapshotActionNode", optional: true, inverse_of: :children
  belongs_to :source_new_action_node, class_name: "NewActionNode", optional: true
  belongs_to :reviewer, class_name: "User", optional: true
  has_many :children, -> { order(:position) }, class_name: "NewDashboardSnapshotActionNode",
                                                 foreign_key: :parent_id, dependent: :destroy, inverse_of: :parent
  has_many :new_dashboard_assignments, dependent: :destroy
  has_many :new_dashboard_node_comments, dependent: :destroy
  has_one :new_dashboard_pack_node_resolution, dependent: :destroy

  validates :node_type, :list_style, :level, :content, :position, presence: true

  default_scope { order(position: :asc) }

  def siblings_with_same_style
    if parent_id
      self.class.unscoped.where(
        new_dashboard_snapshot_task_id: new_dashboard_snapshot_task_id,
        parent_id: parent_id,
        deleted_at: nil
      ).where(list_style: list_style)
    else
      self.class.unscoped.where(
        new_dashboard_snapshot_task_id: new_dashboard_snapshot_task_id,
        parent_id: nil,
        deleted_at: nil
      ).where(list_style: list_style)
    end
  end
end
