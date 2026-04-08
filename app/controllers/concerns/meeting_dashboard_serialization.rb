# frozen_string_literal: true

module MeetingDashboardSerialization
  extend ActiveSupport::Concern
  include NodeTreeSerializer

  private

  # Mirrors TaskController#serialize_flat_with_counters for duck-typed nodes (NewActionNode / snapshot nodes).
  def serialize_flat_with_counters(tree_nodes)
    tree_nodes.map do |tree_item|
      node = serialize_meeting_node_with_counter(tree_item[:node], tree_item[:display_counter])
      node["children"] = tree_item[:children].any? ? serialize_flat_with_counters(tree_item[:children]) : []
      node
    end
  end

  def serialize_meeting_node_with_counter(node, display_counter)
    reviewer = node.respond_to?(:reviewer) ? node.reviewer : nil
    {
      "id" => node.id,
      "stable_node_id" => node.stable_node_id,
      "content" => node.content,
      "level" => node.level,
      "list_style" => node.list_style,
      "node_type" => node.node_type,
      "position" => node.position,
      "review_date" => node.review_date,
      "completed" => node.completed,
      "parent_id" => node.parent_id,
      "display_counter" => display_counter,
      "reviewer_id" => node.reviewer_id,
      "reviewer_name" => reviewer&.first_name
    }
  end

  def serialize_meeting_new_tasks(tasks, pack_stats_by_task_id: {})
    tasks.map do |task|
      serialize_meeting_new_task(task, pack_node_stats: pack_stats_by_task_id[task.id])
    end
  end

  def serialize_meeting_new_task(task, pack_node_stats: nil)
    base = task.as_json
    tree = task.node_tree
    calculate_display_counters(tree)
    counters_map = {}
    walk_counters = lambda do |nodes|
      nodes.each do |item|
        counters_map[item[:node].id] = item[:display_counter]
        walk_counters.call(item[:children]) if item[:children].any?
      end
    end
    walk_counters.call(tree)
    action_nodes_json = serialize_flat_with_counters(tree)
    html_content = task.html_formatted_content(counters_map, tree)

    base.merge!(
      "meeting_dashboard_draft" => true,
      "action_to_be_taken" => html_content,
      "current_version" => {
        "id" => nil,
        "version_number" => nil,
        "status" => "meeting_draft",
        "editor_name" => task.editor&.full_name,
        "editor_id" => task.editor_id,
        "action_nodes" => action_nodes_json
      },
      "editor_name" => task.editor&.full_name,
      "editor_id" => task.editor_id,
      "reviewer_info" => task.reviewer_info,
      "tags" => task.tags.order(:name).map { |t| { "id" => t.id, "name" => t.name } }
    )
    base["pack_node_stats"] = pack_node_stats || {
      "unresolved_count" => 0,
      "resolved_count" => 0,
      "assigned_without_comment_count" => 0,
      "has_action_nodes" => task.new_action_nodes.any?
    }
    base
  end

  def serialize_meeting_snapshot_tasks(version)
    version.new_dashboard_snapshot_tasks.order(:display_position).map do |st|
      serialize_meeting_snapshot_task(st, version)
    end
  end

  # Tags at publish time are stored on the snapshot row as published_tag_ids (see MeetingDashboard::Publisher).
  def snapshot_task_tags_for_json(st)
    raw = st.read_attribute(:published_tag_ids)
    ids =
      case raw
      when Array
        raw.map { |x| Integer(x) rescue nil }.compact.uniq
      when String
        # Legacy / malformed JSON string — ignore
        []
      else
        []
      end
    return [] if ids.empty?

    Tag.where(id: ids).order(:name).pluck(:id, :name).map do |id, name|
      { "id" => id, "name" => name }
    end
  end

  def serialize_meeting_snapshot_task(st, version)
    tree = st.node_tree
    calculate_display_counters(tree)
    counters_map = {}
    walk_counters = lambda do |nodes|
      nodes.each do |item|
        counters_map[item[:node].id] = item[:display_counter]
        walk_counters.call(item[:children]) if item[:children].any?
      end
    end
    walk_counters.call(tree)
    action_nodes_json = serialize_flat_with_counters(tree)
    html_content = st.html_formatted_content(counters_map, tree)

    {
      "id" => st.source_new_task_id || st.id,
      "new_dashboard_snapshot_task_id" => st.id,
      "sector_division" => st.sector_division,
      "description" => st.description,
      "original_date" => st.original_date,
      "review_date" => st.review_date,
      "responsibility" => st.responsibility,
      "status" => NewTask.statuses.key(st.read_attribute(:status)) || "draft",
      "created_at" => st.created_at,
      "updated_at" => st.updated_at,
      "completed_at" => st.completed_at,
      "editor_id" => st.editor_id,
      "editor_name" => st.editor&.full_name,
      "action_to_be_taken" => html_content,
      "current_version" => {
        "id" => version.id,
        "version_number" => nil,
        "status" => "published",
        "editor_name" => version.published_by&.full_name,
        "editor_id" => version.published_by_id,
        "action_nodes" => action_nodes_json
      },
      "reviewer_info" => st.reviewer_info,
      "tags" => snapshot_task_tags_for_json(st),
      "meeting_dashboard_version_id" => version.id,
      "target_meeting_date" => version.target_meeting_date,
      "published_at" => version.published_at,
      "meeting_dashboard_published" => true
    }
  end
end
