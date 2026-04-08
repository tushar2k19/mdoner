# frozen_string_literal: true

require "test_helper"

class MeetingPackNotificationsFlowTest < ActionDispatch::IntegrationTest
  def setup
    @prev_flag = Rails.configuration.x.meeting_dashboard_enabled
    Rails.configuration.x.meeting_dashboard_enabled = true

    @editor = build_user(role: :editor, first_name: "Pack", last_name: "Editor")
    @reviewer = build_user(role: :reviewer, first_name: "Pack", last_name: "Reviewer")
    @editor_auth = auth_headers_for(@editor)
    @reviewer_auth = auth_headers_for(@reviewer)
  end

  def teardown
    Rails.configuration.x.meeting_dashboard_enabled = @prev_flag
  end

  test "assignment create emits R1 meeting notification and not legacy row" do
    fixture = create_published_pack_with_single_node

    assert_difference -> { MeetingPackNotification.count }, +1 do
      assert_no_difference -> { Notification.where(recipient_id: @reviewer.id).count } do
        post "/meeting_dashboard/assignments",
             params: {
               new_dashboard_version_id: fixture[:version].id,
               stable_node_id: fixture[:stable_node_id],
               user_id: @reviewer.id
             },
             headers: @editor_auth,
             as: :json
      end
    end
    assert_response :success, -> { response.body }

    n = MeetingPackNotification.order(:id).last
    assert_equal @reviewer.id, n.user_id
    assert_equal MeetingPackNotification::KIND_PACK_ASSIGNMENT_CREATED, n.kind
    assert_includes n.body, "Editor needs inputs from you on Node"
    assert_equal fixture[:version].id, n.payload["new_dashboard_version_id"]
    assert_equal fixture[:stable_node_id], n.payload["stable_node_id"]
  end

  test "editor comment emits R2 to assignees and reviewer comment emits E1 to editor" do
    fixture = create_published_pack_with_single_node
    post "/meeting_dashboard/assignments",
         params: {
           new_dashboard_version_id: fixture[:version].id,
           stable_node_id: fixture[:stable_node_id],
           user_id: @reviewer.id
         },
         headers: @editor_auth,
         as: :json
    assert_response :success, -> { response.body }
    MeetingPackNotification.delete_all

    assert_difference -> { MeetingPackNotification.count }, +1 do
      post "/meeting_dashboard/dashboard_node_comments",
           params: {
             new_dashboard_version_id: fixture[:version].id,
             stable_node_id: fixture[:stable_node_id],
             body: "Need input."
           },
           headers: @editor_auth,
           as: :json
    end
    assert_response :success, -> { response.body }
    r2 = MeetingPackNotification.order(:id).last
    assert_equal @reviewer.id, r2.user_id
    assert_equal MeetingPackNotification::KIND_DASHBOARD_NODE_COMMENT_FOR_ASSIGNEES, r2.kind
    assert_equal "New comments added on Node 1. Check now!!", r2.body

    MeetingPackNotification.delete_all
    assert_difference -> { MeetingPackNotification.count }, +1 do
      post "/meeting_dashboard/dashboard_node_comments",
           params: {
             new_dashboard_version_id: fixture[:version].id,
             stable_node_id: fixture[:stable_node_id],
             body: "Added reviewer comment."
           },
           headers: @reviewer_auth,
           as: :json
    end
    assert_response :success, -> { response.body }
    e1 = MeetingPackNotification.order(:id).last
    assert_equal @editor.id, e1.user_id
    assert_equal MeetingPackNotification::KIND_DASHBOARD_NODE_COMMENT_FOR_EDITORS, e1.kind
    assert_equal "New comments added on Node 1. Check now!!", e1.body
  end

  test "hub reminder enforces cooldown and returns retry hint" do
    fixture = create_published_pack_with_single_node
    post "/meeting_dashboard/assignments",
         params: {
           new_dashboard_version_id: fixture[:version].id,
           stable_node_id: fixture[:stable_node_id],
           user_id: @reviewer.id
         },
         headers: @editor_auth,
         as: :json
    assert_response :success, -> { response.body }
    MeetingPackNotification.delete_all

    assert_difference -> { MeetingPackNotification.count }, +1 do
      post "/meeting_dashboard/hub_reminder",
           params: {
             new_dashboard_version_id: fixture[:version].id,
             stable_node_id: fixture[:stable_node_id]
           },
           headers: @editor_auth,
           as: :json
    end
    assert_response :success, -> { response.body }

    assert_no_difference -> { MeetingPackNotification.count } do
      post "/meeting_dashboard/hub_reminder",
           params: {
             new_dashboard_version_id: fixture[:version].id,
             stable_node_id: fixture[:stable_node_id]
           },
           headers: @editor_auth,
           as: :json
    end
    assert_response :too_many_requests, -> { response.body }
    body = response.parsed_body
    assert_equal "Please wait before sending another reminder", body["error"]
    assert_equal 600, body["retry_after_seconds"]
  end

  test "meeting notification api lists and marks read" do
    fixture = create_published_pack_with_single_node
    post "/meeting_dashboard/assignments",
         params: {
           new_dashboard_version_id: fixture[:version].id,
           stable_node_id: fixture[:stable_node_id],
           user_id: @reviewer.id
         },
         headers: @editor_auth,
         as: :json
    assert_response :success, -> { response.body }

    get "/meeting_pack_notifications", headers: @reviewer_auth
    assert_response :success, -> { response.body }
    rows = response.parsed_body
    assert rows.is_a?(Array)
    assert rows.any?

    id = rows.first["id"]
    put "/meeting_pack_notifications/#{id}/read", headers: @reviewer_auth
    assert_response :success, -> { response.body }
    assert response.parsed_body.dig("notification", "read_at").present?

    put "/meeting_pack_notifications/read_all", headers: @reviewer_auth
    assert_response :success, -> { response.body }
    assert_equal true, response.parsed_body["success"]
  end

  private

  def auth_headers_for(user)
    post "/signin",
         params: { email: user.email, password: "Password!23" },
         as: :json
    assert_response :success, -> { response.body }
    access = response.parsed_body["access"]
    { "Authorization" => "Bearer #{access}" }
  end

  def create_published_pack_with_single_node
    task = NewTask.create!(
      sector_division: "IFD",
      description: "Meeting notification fixture",
      original_date: Time.current,
      review_date: Time.current,
      responsibility: "Unit",
      editor: @editor,
      status: :draft
    )
    node = task.new_action_nodes.create!(
      content: "Node one",
      level: 1,
      list_style: "decimal",
      node_type: "point",
      position: 1
    )

    post "/meeting_dashboard/publish",
         params: { target_meeting_date: Date.current.to_s },
         headers: @editor_auth,
         as: :json
    assert_response :success, -> { response.body }
    version = NewDashboardVersion.find(response.parsed_body["new_dashboard_version_id"])

    {
      task: task,
      node: node,
      version: version,
      stable_node_id: node.stable_node_id.to_s
    }
  end
end
