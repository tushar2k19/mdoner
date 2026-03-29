# frozen_string_literal: true

require "test_helper"

class ReviewBaselineReviewerSerializationTest < ActiveSupport::TestCase
  setup do
    @data = build_task_with_node_hierarchy
    @task = @data[:task]
    @reviewer_user = @data[:reviewer]
    @version = @task.current_version
    @point2 = @data[:nodes][:point2]
    @controller = ReviewController.new
  end

  test "serialize_node_tree_with_diff includes reviewer_id and reviewer_name when node has reviewer" do
    tree = @version.reload.node_tree
    @controller.send(:calculate_display_counters, tree)
    payload = @controller.send(:serialize_node_tree_with_diff, tree, {})
    entry = find_node_in_tree(payload, @point2.id)
    assert_not_nil entry, "expected point2 in serialized tree"
    assert_equal @reviewer_user.id, entry[:reviewer_id]
    assert_equal @reviewer_user.full_name, entry[:reviewer_name]
  end

  def find_node_in_tree(items, id)
    items.each do |item|
      n = item[:node]
      return n if n[:id] == id
      if item[:children].present?
        found = find_node_in_tree(item[:children], id)
        return found if found
      end
    end
    nil
  end
end
