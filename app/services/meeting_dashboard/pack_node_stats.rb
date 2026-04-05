# frozen_string_literal: true

module MeetingDashboard
  # Per-task aggregates for Tentative draft list against the latest published pack
  # (same version as MeetingDashboardController#draft latest_published).
  #
  # Hub parity: a node counts toward unresolved_count iff it would appear as a row in
  # frontend reviewHubMatrix (assigned OR commented) and is not editor-resolved.
  # assigned_without_comment_count: assignment exists and comment_count == 0.
  # has_action_nodes: live draft NewTask tree (new_action_nodes), not the snapshot.
  class PackNodeStats
    def self.for_tasks(version:, tasks:)
      new(version: version, tasks: tasks).call
    end

    def initialize(version:, tasks:)
      @version = version
      @tasks = tasks
    end

    def call
      by_id = {}
      @tasks.each do |task|
        by_id[task.id] = empty_row(task)
      end
      return by_id if @version.blank?

      task_ids = @tasks.map(&:id)
      pairs = NewDashboardSnapshotActionNode
              .joins(:new_dashboard_snapshot_task)
              .where(new_dashboard_snapshot_tasks: {
                       new_dashboard_version_id: @version.id,
                       source_new_task_id: task_ids
                     })
              .pluck("new_dashboard_snapshot_tasks.source_new_task_id", :id)

      task_to_node_ids = pairs.group_by(&:first).transform_values { |rows| rows.map(&:last) }
      node_ids = pairs.map(&:last).uniq
      return by_id if node_ids.empty?

      comment_counts = NewDashboardNodeComment.where(new_dashboard_version_id: @version.id)
                                               .where(new_dashboard_snapshot_action_node_id: node_ids)
                                               .group(:new_dashboard_snapshot_action_node_id)
                                               .count

      assigned_node_ids = NewDashboardAssignment.where(new_dashboard_version_id: @version.id)
                                                  .where(new_dashboard_snapshot_action_node_id: node_ids)
                                                  .distinct
                                                  .pluck(:new_dashboard_snapshot_action_node_id)
                                                  .to_set

      resolutions = NewDashboardPackNodeResolution.where(new_dashboard_version_id: @version.id)
                                                    .where(new_dashboard_snapshot_action_node_id: node_ids)
                                                    .index_by(&:new_dashboard_snapshot_action_node_id)

      task_ids.each do |tid|
        nids = task_to_node_ids[tid] || []
        u = c_assigned_no_comment = resolved = 0
        nids.each do |nid|
          cc = comment_counts[nid].to_i
          assigned = assigned_node_ids.include?(nid)
          in_hub = cc.positive? || assigned
          rec = resolutions[nid]
          is_resolved = rec&.resolved == true

          c_assigned_no_comment += 1 if assigned && cc.zero?
          resolved += 1 if is_resolved
          u += 1 if !is_resolved && in_hub
        end

        by_id[tid] = {
          "unresolved_count" => u,
          "resolved_count" => resolved,
          "assigned_without_comment_count" => c_assigned_no_comment,
          "has_action_nodes" => by_id[tid]["has_action_nodes"]
        }
      end

      by_id
    end

    private

    def empty_row(task)
      {
        "unresolved_count" => 0,
        "resolved_count" => 0,
        "assigned_without_comment_count" => 0,
        "has_action_nodes" => task.new_action_nodes.any?
      }
    end
  end
end
