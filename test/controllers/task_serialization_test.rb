require "test_helper"

class TaskSerializationTest < ActiveSupport::TestCase
  def setup
    @data = build_task_with_node_hierarchy
    @task = @data[:task]
    @controller = TaskController.new
  end

  test "serialize_task_with_version returns nested action nodes with counters" do
    payload = @controller.send(:serialize_task_with_version, @task.reload)
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

    tasks = Task.where(id: [@task.id, second_task.id]).order(:id)
    payload = @controller.send(:serialize_tasks_with_versions, tasks)

    current_task_payload = payload.find { |hash| hash["id"] == @task.id }
    reviewer_name = current_task_payload["current_version"]["action_nodes"][1]["reviewer_name"]

    assert_equal "Reviewer", reviewer_name
  end
end



