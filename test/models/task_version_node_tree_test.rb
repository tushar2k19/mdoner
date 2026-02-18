require "test_helper"

class TaskVersionNodeTreeTest < ActiveSupport::TestCase
  def setup
    data = build_task_with_node_hierarchy
    @version = data[:version]
    @nodes = data[:nodes]
  end

  test "node_tree returns nested hierarchy with children in positional order" do
    tree = @version.node_tree

    assert_equal 3, tree.length
    assert_equal @nodes[:point1].id, tree.first[:node].id
    assert_equal [@nodes[:subpoint1].id, @nodes[:subpoint2].id],
                 tree.first[:children].map { |child| child[:node].id }

    point3_branch = tree.third
    assert_equal @nodes[:point3].id, point3_branch[:node].id
    assert_equal @nodes[:subsubpoint1].id,
                 point3_branch[:children].first[:children].first[:node].id
  end

  test "display_counter honors list style hierarchy" do
    assert_equal "1", @nodes[:point1].display_counter
    assert_equal "a", @nodes[:subpoint1].display_counter
    assert_equal "b", @nodes[:subpoint2].display_counter
    assert_equal "2", @nodes[:point2].display_counter
    assert_equal "i", @nodes[:subsubpoint1].display_counter
  end
end



