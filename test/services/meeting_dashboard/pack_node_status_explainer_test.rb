require "test_helper"

class PackNodeStatusExplainerTest < ActiveSupport::TestCase
  setup do
    @editor = User.create!(role: "editor", email: "editor@example.com", first_name: "Editor", password: "password")
    @reviewer = User.create!(role: "reviewer", email: "reviewer@example.com", first_name: "Rev", password: "password")
    
    @task = NewTask.new(status: :draft, sector_division: "Tech", description: "Desc", original_date: Date.current, responsibility: "Me", review_date: Date.current)
    @task.save(validate: false)
    NewActionNode.create!(new_task: @task, node_type: "rich_text", list_style: "decimal", content: "hi", level: 1, position: 1)
    
    @version = NewDashboardVersion.create!(
      target_meeting_date: Date.current,
      published_at: Time.current,
      published_by: @editor
    )

    @snap_task = NewDashboardSnapshotTask.new(
      new_dashboard_version: @version,
      source_new_task_id: @task.id,
      sector_division: "Tech",
      description: "Desc",
      original_date: Date.current,
      responsibility: "Me",
      review_date: Date.current,
      status: "draft",
      display_position: 1
    )
    @snap_task.save(validate: false)

    @snap_a = create_snap("Node A", "1", "decimal", 1)
    @snap_b = create_snap("Node B", "2", "decimal", 2)
    @snap_b_a = create_snap("Child B.a", "2a", "lower-alpha", 1, @snap_b)
    @snap_c = create_snap("Node C", "3", "decimal", 3)
    @snap_d = create_snap("Node D", "4", "decimal", 4)
  end

  def create_snap(content, stable_id, list_style, position, parent = nil)
    snap = NewDashboardSnapshotActionNode.new(
      new_dashboard_snapshot_task: @snap_task,
      new_dashboard_version: @version,
      parent: parent,
      content: content,
      level: parent ? 2 : 1,
      list_style: list_style,
      node_type: "rich_text",
      position: position,
      stable_node_id: stable_id
    )
    snap.save(validate: false)
    snap
  end

  test "assigned + 0 comments + unresolved" do
    NewDashboardAssignment.create!(new_dashboard_version: @version, new_dashboard_snapshot_action_node: @snap_a, user: @reviewer)
    
    res = MeetingDashboard::PackNodeStatusExplainer.call(version: @version, task: @task)
    
    assert_equal 1, res[:summary][:counts][:red]
    assert_equal 0, res[:summary][:counts][:green]
    assert_equal 1, res[:summary][:counts][:assigned_without_comment]
    assert_equal "Pending Action", res[:summary][:pending_label_reason]
    
    red_item = res[:red_items].first
    assert_equal "assigned_no_comment", red_item[:reason_code]
  end

  test "assigned + comments + unresolved" do
    NewDashboardAssignment.create!(new_dashboard_version: @version, new_dashboard_snapshot_action_node: @snap_b_a, user: @reviewer)
    NewDashboardNodeComment.create!(new_dashboard_version: @version, new_dashboard_snapshot_action_node: @snap_b_a, user: @reviewer, body: "Comment")
    
    res = MeetingDashboard::PackNodeStatusExplainer.call(version: @version, task: @task)
    
    assert_equal 1, res[:summary][:counts][:red]
    assert_equal 0, res[:summary][:counts][:assigned_without_comment]
    
    red_item = res[:red_items].first
    assert_equal "assigned_commented_unresolved", red_item[:reason_code]
  end

  test "unassigned + comments + unresolved" do
    NewDashboardNodeComment.create!(new_dashboard_version: @version, new_dashboard_snapshot_action_node: @snap_c, user: @reviewer, body: "Feedback")
    
    res = MeetingDashboard::PackNodeStatusExplainer.call(version: @version, task: @task)
    
    red_item = res[:red_items].first
    assert_equal "commented_unassigned_unresolved", red_item[:reason_code]
  end

  test "resolved with comments" do
    NewDashboardNodeComment.create!(new_dashboard_version: @version, new_dashboard_snapshot_action_node: @snap_d, user: @reviewer, body: "Done")
    NewDashboardPackNodeResolution.create!(new_dashboard_version: @version, new_dashboard_snapshot_action_node: @snap_d, resolved: true, resolved_at: Time.current, resolved_by: @editor)
    
    res = MeetingDashboard::PackNodeStatusExplainer.call(version: @version, task: @task)
    
    assert_equal 0, res[:summary][:counts][:red]
    assert_equal 1, res[:summary][:counts][:green]
    assert_equal "Ready to be published", res[:summary][:pending_label_reason]
    
    green_item = res[:green_items].first
    assert_equal "resolved", green_item[:reason_code]
  end
end
