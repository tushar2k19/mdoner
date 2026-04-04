# frozen_string_literal: true

module MeetingDashboard
  # Ordered list of snapshot nodes that have at least one comment (for editor navigation).
  class CommentNodesIndex
    def self.call(version)
      new(version).call
    end

    def initialize(version)
      @version = version
    end

    def call
      return [] unless @version

      node_ids_with_comments = NewDashboardNodeComment.where(new_dashboard_version_id: @version.id)
                                                      .distinct
                                                      .pluck(:new_dashboard_snapshot_action_node_id)
      return [] if node_ids_with_comments.empty?

      id_set = node_ids_with_comments.index_with { true }
      ordered = []

      @version.new_dashboard_snapshot_tasks.order(:display_position).each do |st|
        walk_tree(st.node_tree, st, id_set, ordered)
      end

      ordered
    end

    private

    def walk_tree(tree, snapshot_task, id_set, acc)
      tree.each do |item|
        node = item[:node]
        if id_set[node.id]
          acc << {
            "new_task_id" => snapshot_task.source_new_task_id,
            "stable_node_id" => node.stable_node_id,
            "snapshot_action_node_id" => node.id
          }
        end
        walk_tree(item[:children], snapshot_task, id_set, acc) if item[:children].any?
      end
    end
  end
end
