# frozen_string_literal: true

module MeetingDashboard
  # Human-readable node label matching frontend `formatNodePathFromSegments` (e.g. "8(c)(iv)").
  class SnapshotNodeLabel
    include NodeTreeSerializer

    class << self
      def build(snap)
        new(snap).build
      end
    end

    def initialize(snap)
      @snap = snap
    end

    def build
      return "—" if @snap.blank?

      task = @snap.new_dashboard_snapshot_task
      return "—" if task.blank?

      tree = task.node_tree
      calculate_display_counters(tree)
      segments = find_segments(tree, @snap.stable_node_id.to_s)
      format_segments(segments)
    end

    private

    def find_segments(nodes, target_stable_id, acc = [])
      nodes.each do |item|
        node = item[:node]
        next_seg = acc + [{ counter: item[:display_counter] }]
        if node.stable_node_id.to_s == target_stable_id
          return next_seg
        end
        if item[:children].any?
          hit = find_segments(item[:children], target_stable_id, next_seg)
          return hit if hit
        end
      end
      nil
    end

    def format_segments(segments)
      return "—" if segments.blank?

      first = segments.first[:counter].to_s.strip
      return "—" if first.blank?

      s = first
      segments.drop(1).each do |seg|
        c = seg[:counter].to_s.strip
        s += "(#{c})" if c.present?
      end
      s.presence || "—"
    end
  end
end
