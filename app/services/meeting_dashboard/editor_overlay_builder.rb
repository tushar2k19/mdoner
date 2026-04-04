# frozen_string_literal: true

module MeetingDashboard
  # Builds per-node overlay for Tentative: assignments + comment counts on a published version,
  # keyed by stable_node_id (stable across draft reset).
  class EditorOverlayBuilder
    def self.call(version)
      new(version).call
    end

    def initialize(version)
      @version = version
    end

    def call
      return { "new_dashboard_version_id" => nil, "nodes" => {} } unless @version

      nodes = NewDashboardSnapshotActionNode.where(new_dashboard_version_id: @version.id)
      node_ids = nodes.pluck(:id)
      return empty_payload if node_ids.empty?

      comment_counts = NewDashboardNodeComment.where(new_dashboard_version_id: @version.id)
                                                .where(new_dashboard_snapshot_action_node_id: node_ids)
                                                .group(:new_dashboard_snapshot_action_node_id)
                                                .count

      last_comment_at = NewDashboardNodeComment.where(new_dashboard_version_id: @version.id)
                                               .where(new_dashboard_snapshot_action_node_id: node_ids)
                                               .group(:new_dashboard_snapshot_action_node_id)
                                               .maximum(:created_at)

      assignments = NewDashboardAssignment.where(new_dashboard_version_id: @version.id)
                                          .where(new_dashboard_snapshot_action_node_id: node_ids)
                                          .includes(:user)
                                          .to_a
      by_snap = assignments.group_by(&:new_dashboard_snapshot_action_node_id)

      out = {}
      nodes.find_each do |snap|
        sid = snap.stable_node_id
        next if sid.blank?

        users = (by_snap[snap.id] || []).map do |a|
          u = a.user
          next unless u

          { "id" => u.id, "name" => u.full_name }
        end.compact.uniq { |h| h["id"] }

        out[sid] = {
          "new_task_id" => snap.new_dashboard_snapshot_task.source_new_task_id,
          "snapshot_action_node_id" => snap.id,
          "assignment_users" => users,
          "comment_count" => comment_counts[snap.id].to_i,
          "last_comment_at" => last_comment_at[snap.id]&.iso8601
        }
      end

      {
        "new_dashboard_version_id" => @version.id,
        "nodes" => out
      }
    end

    private

    def empty_payload
      { "new_dashboard_version_id" => @version.id, "nodes" => {} }
    end
  end
end
