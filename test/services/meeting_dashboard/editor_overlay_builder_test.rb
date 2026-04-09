# frozen_string_literal: true

require "test_helper"

class MeetingDashboard::EditorOverlayBuilderTest < ActiveSupport::TestCase
  setup do
    @editor = User.create!(role: "editor", email: "editor_overlay@example.com", first_name: "Ed", password: "password")

    @task = NewTask.new(status: :draft, sector_division: "Tech", description: "Desc", original_date: Date.current,
                        responsibility: "Me", review_date: Date.current)
    @task.save(validate: false)

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

  test "returns new_task_id per stable node" do
    out = MeetingDashboard::EditorOverlayBuilder.call(@version)

    assert_equal @version.id, out["new_dashboard_version_id"]
    assert_equal @task.id, out["nodes"]["1"]["new_task_id"]
    assert_equal @snap_a.id, out["nodes"]["1"]["snapshot_action_node_id"]
  end

  test "does not issue one SELECT per action node for snapshot tasks" do
    8.times { |i| create_snap("Extra #{i}", "e#{i}", "decimal", 10 + i) }

    selective_queries = 0
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") do |*, payload|
      next if payload[:cached]
      sql = payload[:sql].to_s
      next unless sql.include?("new_dashboard_snapshot_tasks") && sql.match?(/\bSELECT\b/i)

      selective_queries += 1
    end

    begin
      out = MeetingDashboard::EditorOverlayBuilder.call(@version)
      assert_operator out["nodes"].size, :>=, 8
    ensure
      ActiveSupport::Notifications.unsubscribe(sub)
    end

    assert_operator selective_queries, :<=, 3,
                    "expected preload (1–2 queries per batch), not per-node SELECTs"
  end
end
