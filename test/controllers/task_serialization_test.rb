require "test_helper"

class TaskSerializationTest < ActiveSupport::TestCase
  def setup
    @data = build_task_with_node_hierarchy
    @task = @data[:task]
    @controller = TaskController.new
  end

  test "serialize_task_with_version returns nested action nodes with counters" do
    task = @controller.send(:task_for_serialization, @task.reload)
    payload = @controller.send(:serialize_task_with_version, task)
    version_payload = payload["current_version"]

    assert_equal @task.current_version.id, version_payload["id"]
    root_nodes = version_payload["action_nodes"]

    assert_equal 3, root_nodes.size
    assert_equal ["1", "2", "3"], root_nodes.map { |node| node["display_counter"] }

    first_children_counters = root_nodes.first["children"].map { |child| child["display_counter"] }
    assert_equal ["a", "b"], first_children_counters

    deep_child = root_nodes.last["children"].first["children"].first
    assert_equal "<sub-subpoint 1>", deep_child["content"]
  end

  test "serialize_tasks_with_versions preserves reviewer metadata" do
    second_task = build_task_with_node_hierarchy[:task]

    tasks = Task.includes(
      :editor,
      :tags,
      current_version: {
        all_action_nodes: [:reviewer, :parent]
      }
    ).where(id: [@task.id, second_task.id]).order(:id)
    payload = @controller.send(:serialize_tasks_with_versions, tasks)

    current_task_payload = payload.find { |hash| hash["id"] == @task.id }
    reviewer_name = current_task_payload["current_version"]["action_nodes"][1]["reviewer_name"]

    assert_equal "Reviewer", reviewer_name
  end

  test "delta apply updates existing node content without changing id" do
    version = @task.current_version
    target_id = @data[:nodes][:subpoint1].id
    payload = payload_for_version(version)

    node_payload = payload.find { |node| node["id"] == target_id }
    node_payload["content"] = "<subpoint 1 updated>"

    before_ids = version.all_action_nodes.pluck(:id).sort
    @controller.send(:apply_action_nodes_delta, version, payload)
    version.reload

    after_ids = version.all_action_nodes.pluck(:id).sort
    updated_node = version.all_action_nodes.find(target_id)

    assert_equal before_ids, after_ids
    assert_equal "<subpoint 1 updated>", updated_node.content
  end

  test "delta apply inserts new sibling and shifts later sibling positions" do
    version = @task.current_version
    point1_id = @data[:nodes][:point1].id
    subpoint1_id = @data[:nodes][:subpoint1].id
    subpoint2_id = @data[:nodes][:subpoint2].id

    payload = payload_for_version(version)
    insert_index = payload.index { |node| node["id"] == subpoint1_id } + 1
    payload.insert(insert_index, {
      "id" => -1,
      "content" => "<inserted subpoint>",
      "level" => 2,
      "list_style" => "lower-alpha",
      "node_type" => "subpoint",
      "parent_id" => point1_id,
      "review_date" => nil,
      "completed" => false,
      "reviewer_id" => nil
    })

    @controller.send(:apply_action_nodes_delta, version, payload)
    version.reload

    inserted = version.all_action_nodes.find_by(content: "<inserted subpoint>")
    shifted = version.all_action_nodes.find(subpoint2_id)

    assert_not_nil inserted
    assert_equal point1_id, inserted.parent_id
    assert_equal 2, inserted.position
    assert_equal 3, shifted.position
  end

  test "delta apply deletes missing node while preserving untouched ids" do
    version = @task.current_version
    deleted_id = @data[:nodes][:subpoint2].id
    untouched_id = @data[:nodes][:point2].id

    payload = payload_for_version(version).reject { |node| node["id"] == deleted_id }
    @controller.send(:apply_action_nodes_delta, version, payload)
    version.reload

    assert_not version.all_action_nodes.exists?(id: deleted_id)
    assert version.all_action_nodes.exists?(id: untouched_id)
  end

  test "delta apply reorders root siblings while keeping ids stable" do
    version = @task.current_version
    point1_id = @data[:nodes][:point1].id
    point2_id = @data[:nodes][:point2].id
    point3_id = @data[:nodes][:point3].id
    subpoint3_id = @data[:nodes][:subpoint3].id
    subsubpoint1_id = @data[:nodes][:subsubpoint1].id
    subpoint1_id = @data[:nodes][:subpoint1].id
    subpoint2_id = @data[:nodes][:subpoint2].id

    payload = payload_for_version(version)

    point1_branch = payload.select { |node| [point1_id, subpoint1_id, subpoint2_id].include?(node["id"]) }
    point2_node = payload.find { |node| node["id"] == point2_id }
    point3_branch = payload.select { |node| [point3_id, subpoint3_id, subsubpoint1_id].include?(node["id"]) }

    reordered_payload = point1_branch + point3_branch + [point2_node]
    before_ids = version.all_action_nodes.pluck(:id).sort

    @controller.send(:apply_action_nodes_delta, version, reordered_payload)
    version.reload

    after_ids = version.all_action_nodes.pluck(:id).sort
    point2 = version.all_action_nodes.find(point2_id)
    point3 = version.all_action_nodes.find(point3_id)

    assert_equal before_ids, after_ids
    assert_equal 2, point3.position
    assert_equal 3, point2.position
  end

  private

  def payload_for_version(version)
    flatten_tree_to_payload(version.node_tree)
  end

  def flatten_tree_to_payload(tree_nodes, output = [])
    tree_nodes.each do |tree_item|
      node = tree_item[:node]
      output << {
        "id" => node.id,
        "content" => node.content,
        "level" => node.level,
        "list_style" => node.list_style,
        "node_type" => node.node_type,
        "parent_id" => node.parent_id,
        "review_date" => node.review_date,
        "completed" => node.completed,
        "reviewer_id" => node.reviewer_id
      }
      flatten_tree_to_payload(tree_item[:children], output) if tree_item[:children].any?
    end
    output
  end
end



