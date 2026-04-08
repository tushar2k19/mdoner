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
      return { "new_dashboard_version_id" => nil, "nodes" => {}, "overlay_user_directory" => [] } unless @version

      nodes = NewDashboardSnapshotActionNode.where(new_dashboard_version_id: @version.id)
      node_ids = nodes.pluck(:id)
      return empty_payload if node_ids.empty?

      comment_counts = NewDashboardNodeComment.where(new_dashboard_version_id: @version.id)
                                                .where(new_dashboard_snapshot_action_node_id: node_ids)
                                                .group(:new_dashboard_snapshot_action_node_id)
                                                .count

      comment_user_ids_by_snap = Hash.new { |h, k| h[k] = [] }
      NewDashboardNodeComment.where(new_dashboard_version_id: @version.id)
                             .where(new_dashboard_snapshot_action_node_id: node_ids)
                             .distinct
                             .pluck(:new_dashboard_snapshot_action_node_id, :user_id)
                             .each do |snap_id, uid|
        comment_user_ids_by_snap[snap_id] << uid if uid
      end
      comment_user_ids_by_snap.each_value(&:uniq!)

      last_comment_at = NewDashboardNodeComment.where(new_dashboard_version_id: @version.id)
                                               .where(new_dashboard_snapshot_action_node_id: node_ids)
                                               .group(:new_dashboard_snapshot_action_node_id)
                                               .maximum(:created_at)

      assignments = NewDashboardAssignment.where(new_dashboard_version_id: @version.id)
                                          .where(new_dashboard_snapshot_action_node_id: node_ids)
                                          .includes(:user)
                                          .to_a
      by_snap = assignments.group_by(&:new_dashboard_snapshot_action_node_id)

      resolution_by_snap_id = NewDashboardPackNodeResolution
                              .where(new_dashboard_version_id: @version.id,
                                     new_dashboard_snapshot_action_node_id: node_ids)
                              .includes(:resolved_by)
                              .index_by(&:new_dashboard_snapshot_action_node_id)

      out = {}
      nodes.find_each do |snap|
        sid = snap.stable_node_id
        next if sid.blank?

        users = (by_snap[snap.id] || []).map do |a|
          u = a.user
          next unless u

          { "id" => u.id, "name" => u.full_name, "assignment_id" => a.id }
        end.compact.uniq { |h| h["id"] }

        res = resolution_by_snap_id[snap.id]
        out[sid] = {
          "new_task_id" => snap.new_dashboard_snapshot_task.source_new_task_id,
          "snapshot_action_node_id" => snap.id,
          "assignment_users" => users,
          "comment_count" => comment_counts[snap.id].to_i,
          "comment_user_ids" => comment_user_ids_by_snap[snap.id] || [],
          "last_comment_at" => last_comment_at[snap.id]&.iso8601,
          "is_resolved" => res&.resolved == true,
          "resolved_at" => res&.resolved_at&.iso8601,
          "resolved_by" => if res&.resolved_by_id
                             { "id" => res.resolved_by_id, "name" => res.resolved_by&.full_name }
                           end
        }
      end

      all_user_ids = []
      out.each_value do |h|
        (h["assignment_users"] || []).each { |u| all_user_ids << u["id"] if u["id"] }
        all_user_ids.concat(h["comment_user_ids"] || [])
      end
      all_user_ids.uniq!
      directory = if all_user_ids.empty?
                    []
                  else
                    User.where(id: all_user_ids).map do |u|
                      { "id" => u.id, "name" => u.full_name }
                    end.sort_by { |h| [h["name"].to_s.downcase, h["id"]] }
                  end

      {
        "new_dashboard_version_id" => @version.id,
        "nodes" => out,
        "overlay_user_directory" => directory
      }
    end

    private

    def empty_payload
      { "new_dashboard_version_id" => @version.id, "nodes" => {}, "overlay_user_directory" => [] }
    end
  end
end
