# frozen_string_literal: true

module MeetingDashboard
  # Single source of truth for explaining "Pending Action" vs "Ready to be published" counts.
  # Mirrors PackNodeStats logic but returns per-node human-readable explanations.
  #
  # Key design decisions to avoid bugs:
  #  - Loads ALL snapshot nodes for the task in ONE query (no joins that duplicate rows).
  #  - Builds parent→children tree in memory and computes counters from that tree.
  #    This exactly matches how reviewHubMatrix.js builds nodeLabel on the frontend.
  #  - No per-node DB calls (no display_counter, no siblings_with_same_style DB hits).
  class PackNodeStatusExplainer
    def self.call(version:, task:)
      new(version: version, task: task).call
    end

    def initialize(version:, task:)
      @version = version
      @task = task
    end

    def call
      # ── 1. Find the snapshot task record ───────────────────────────────────
      snap_task = NewDashboardSnapshotTask.find_by(
        new_dashboard_version_id: @version.id,
        source_new_task_id: @task.id
      )

      return empty_result unless snap_task

      # ── 2. Load ALL nodes for this snapshot task (no join, no duplicates) ──
      all_nodes = NewDashboardSnapshotActionNode
                  .where(new_dashboard_version_id: @version.id,
                         new_dashboard_snapshot_task_id: snap_task.id)
                  .to_a

      return empty_result if all_nodes.empty?

      node_ids = all_nodes.map(&:id)

      # ── 3. Batch-load comment counts, assignments, resolutions ─────────────
      comment_counts = NewDashboardNodeComment
                       .where(new_dashboard_version_id: @version.id,
                              new_dashboard_snapshot_action_node_id: node_ids)
                       .group(:new_dashboard_snapshot_action_node_id)
                       .count

      assigned_node_ids = NewDashboardAssignment
                          .where(new_dashboard_version_id: @version.id,
                                 new_dashboard_snapshot_action_node_id: node_ids)
                          .distinct
                          .pluck(:new_dashboard_snapshot_action_node_id)
                          .to_set

      resolutions = NewDashboardPackNodeResolution
                    .where(new_dashboard_version_id: @version.id,
                           new_dashboard_snapshot_action_node_id: node_ids)
                    .index_by(&:new_dashboard_snapshot_action_node_id)

      # ── 4. Build in-memory tree and compute labels ──────────────────────────
      node_by_id = all_nodes.index_by(&:id)
      node_labels = build_labels_in_memory(all_nodes, node_by_id)

      # ── 5. Walk each node and categorise ───────────────────────────────────
      red_items = []
      green_items = []
      c_assigned_no_comment = 0
      resolved_count = 0
      unresolved_count = 0

      all_nodes.each do |node|
        nid       = node.id
        cc        = comment_counts[nid].to_i
        assigned  = assigned_node_ids.include?(nid)
        in_hub    = cc.positive? || assigned
        rec       = resolutions[nid]
        is_resolved = rec&.resolved == true

        # Skip nodes that have no activity at all
        next unless in_hub

        node_label = node_labels[nid] || "—"
        stable_id  = node.stable_node_id
        reason_code = nil
        message     = nil
        bucket      = nil

        if assigned && cc.zero?
          # Assigned but zero comments — always RED regardless of resolution flag.
          c_assigned_no_comment += 1
          reason_code = "assigned_no_comment"
          if is_resolved
            message = "is marked **resolved**, but it is assigned and has received zero pack comments. " \
                      "Assignments require at least one comment to clear 'Pending Action'."
          else
            message = "has been assigned but has not yet received any pack comments"
          end
          bucket = :red
        elsif is_resolved
          # Has comments AND is resolved → cleared (green)
          resolved_count += 1
          reason_code = "resolved"
          message = "is marked resolved (pack comments were recorded on this node)"
          bucket = :green
        elsif assigned
          # Assigned + has comments + not resolved → red
          unresolved_count += 1
          reason_code = "assigned_commented_unresolved"
          message = "has been assigned and received comments but has not been marked resolved"
          bucket = :red
        else
          # Commented, not assigned, not resolved (blue in hub) → red until resolved
          unresolved_count += 1
          reason_code = "commented_unassigned_unresolved"
          message = "has received comments but has not been marked resolved"
          bucket = :red
        end

        item = {
          stable_node_id: stable_id,
          node_label:     node_label,
          reason_code:    reason_code,
          message:        message,
          meta: {
            assigned:       assigned,
            comments_count: cc,
            resolved:       is_resolved
          }
        }

        bucket == :red ? red_items << item : green_items << item
      end

      has_action_nodes = @task.new_action_nodes.any?
      no_action_nodes  = !has_action_nodes
      is_fully_clear   = !no_action_nodes && unresolved_count == 0 && c_assigned_no_comment == 0

      summary = {
        pending_label_reason: is_fully_clear ? "Ready to be published" : "Pending Action",
        ready_eligible:       is_fully_clear,
        counts: {
          red:                       unresolved_count + c_assigned_no_comment,
          green:                     resolved_count,
          assigned_without_comment:  c_assigned_no_comment,
          unresolved:                unresolved_count
        }
      }

      {
        summary:     summary,
        red_items:   red_items.sort_by { |i| i[:node_label] },
        green_items: green_items.sort_by { |i| i[:node_label] }
      }
    end

    private

    # Build node labels entirely in memory — matching reviewHubMatrix.js formatNodePathFromSegments.
    # Groups siblings by (parent_id, list_style) and sorts by position to get positional counter.
    def build_labels_in_memory(all_nodes, node_by_id)
      # Build children map: parent_id → sorted children
      children_map = Hash.new { |h, k| h[k] = [] }
      all_nodes.each do |n|
        children_map[n.parent_id] << n
      end
      # Sort each sibling group by position
      children_map.each_value { |arr| arr.sort_by!(&:position) }

      labels = {}
      # Precompute ancestor path for each node
      all_nodes.each do |node|
        path = []
        cur  = node
        while cur
          path.unshift(cur)
          cur = cur.parent_id ? node_by_id[cur.parent_id] : nil
        end

        label = format_path(path, children_map)
        labels[node.id] = label
      end

      labels
    end

    def format_path(path, children_map)
      return "—" if path.empty?

      segments = path.map.with_index do |node, idx|
        parent_id   = idx == 0 ? nil : path[idx - 1].id
        siblings    = siblings_for(node, parent_id, children_map)
        same_style  = siblings.select { |s| s.list_style == node.list_style }
        pos         = same_style.index(node).to_i + 1
        counter_string(node.list_style, pos)
      end

      first = segments[0].to_s.strip
      return "—" if first.blank?

      result = first
      segments[1..].each do |seg|
        result += "(#{seg})" if seg.present?
      end
      result
    end

    # Returns siblings of `node` under `parent_id` from the in-memory children_map
    def siblings_for(node, parent_id, children_map)
      children_map[parent_id].presence || [node]
    end

    def counter_string(list_style, position)
      case list_style
      when "decimal"      then position.to_s
      when "lower-alpha"  then (96 + position).chr
      when "lower-roman"  then to_roman(position).downcase
      when "bullet"       then "•"
      else position.to_s
      end
    end

    def to_roman(number)
      return "" if number <= 0
      values   = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
      literals = %w[M CM D CD C XC L XL X IX V IV I]
      roman    = ""
      values.each_with_index do |value, index|
        count   = number / value
        roman  += literals[index] * count
        number -= value * count
      end
      roman
    end

    def empty_result
      {
        summary: {
          pending_label_reason: "Pending Action",
          ready_eligible:       false,
          counts: { red: 0, green: 0, assigned_without_comment: 0, unresolved: 0 }
        },
        red_items:   [],
        green_items: []
      }
    end
  end
end
