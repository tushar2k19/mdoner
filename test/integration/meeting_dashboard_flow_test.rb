# frozen_string_literal: true

require "test_helper"

class MeetingDashboardFlowTest < ActionDispatch::IntegrationTest
  def setup
    @prev_flag = Rails.configuration.x.meeting_dashboard_enabled
    Rails.configuration.x.meeting_dashboard_enabled = true

    @editor = build_user(role: :editor, first_name: "Ed", last_name: "Itor")
    post "/signin",
         params: { email: @editor.email, password: "Password!23" },
         as: :json
    assert_response :success, -> { response.body }
    @access = response.parsed_body["access"]
    assert @access.present?
    @auth = { "Authorization" => "Bearer #{@access}" }
  end

  def teardown
    Rails.configuration.x.meeting_dashboard_enabled = @prev_flag
  end

  test "meeting_dashboard draft returns success and empty lists when no new tasks" do
    get "/meeting_dashboard/draft", headers: @auth, params: { date: Date.current }
    assert_response :success
    body = response.parsed_body
    assert_equal [], body["active"]
    assert_equal [], body["completed"]
    assert_nil body["latest_published"]
  end

  test "meeting_dashboard disabled returns not found" do
    Rails.configuration.x.meeting_dashboard_enabled = false
    get "/meeting_dashboard/draft", headers: @auth, params: { date: Date.current }
    assert_response :not_found
  end

  test "import approve accepts responsibility longer than 255 chars" do
    long_resp = (["JS(AD)"] * 80).join(", ")
    assert_operator long_resp.length, :>, 255

    payload = {
      task: { sn: 88, sector_division: "IFD", description: "Long resp test", responsibility: long_resp },
      nodes: [
        {
          "id" => "n1",
          "parent_id" => nil,
          "content" => "<p>ok</p>",
          "level" => 1,
          "list_style" => "decimal",
          "node_type" => "rich_text",
          "position" => 1
        }
      ]
    }
    post "/imports/dashboard_html/approve",
         params: payload,
         headers: @auth,
         as: :json
    assert_response :success, -> { response.body }
    nt = NewTask.find(response.parsed_body["task_id"])
    assert_equal long_resp, nt.responsibility
  end

  test "import approve creates new_task and node when meeting flag on" do
    payload = {
      task: { sn: 1, sector_division: "IFD", description: "Demo", responsibility: "All JS" },
      nodes: [
        {
          "id" => "n1",
          "parent_id" => nil,
          "content" => "<p>hello</p>",
          "level" => 1,
          "list_style" => "decimal",
          "node_type" => "rich_text",
          "position" => 1
        }
      ]
    }
    post "/imports/dashboard_html/approve",
         params: payload,
         headers: @auth,
         as: :json
    assert_response :success, -> { response.body }
    data = response.parsed_body
    assert_equal true, data["meeting_dashboard"]
    assert_nil data["task_version_id"]
    nt = NewTask.find(data["task_id"])
    assert_equal 1, nt.new_action_nodes.count
  end

  test "publish then published returns snapshot tasks" do
    nt = NewTask.create!(
      sector_division: "S",
      description: "D",
      original_date: Time.current,
      review_date: Time.current,
      responsibility: "R",
      editor: @editor,
      status: :draft
    )
    nt.new_action_nodes.create!(
      content: "body",
      level: 1,
      list_style: "decimal",
      node_type: "point",
      position: 1
    )

    post "/meeting_dashboard/publish",
         params: { target_meeting_date: Date.current.to_s },
         headers: @auth,
         as: :json
    assert_response :success, -> { response.body }
    pub = response.parsed_body
    assert pub["new_dashboard_version_id"].present?

    get "/meeting_dashboard/published",
        headers: @auth,
        params: { meeting_date: Date.current }
    assert_response :success
    body = response.parsed_body
    assert_equal false, body["empty"]
    assert_equal 1, body["tasks"].length
    assert_equal "body", body["tasks"].first["current_version"]["action_nodes"].first["content"]
  end

  test "published by new_dashboard_version_id returns snapshot and schedule_meeting_date" do
    nt = NewTask.create!(
      sector_division: "S",
      description: "D",
      original_date: Time.current,
      review_date: Time.current,
      responsibility: "R",
      editor: @editor,
      status: :draft
    )
    nt.new_action_nodes.create!(
      content: "by-version",
      level: 1,
      list_style: "decimal",
      node_type: "point",
      position: 1
    )

    post "/meeting_dashboard/publish",
         params: { target_meeting_date: Date.current.to_s },
         headers: @auth,
         as: :json
    assert_response :success, -> { response.body }
    version_id = response.parsed_body["new_dashboard_version_id"]

    get "/meeting_dashboard/published",
        headers: @auth,
        params: { new_dashboard_version_id: version_id }
    assert_response :success
    body = response.parsed_body
    assert_equal false, body["empty"]
    assert_equal version_id, body["meeting_dashboard_version_id"]
    assert_equal Date.current.to_s, body["schedule_meeting_date"].to_s
    assert_equal "by-version", body["tasks"].first["current_version"]["action_nodes"].first["content"]

    get "/meeting_dashboard/published",
        headers: @auth,
        params: { dashboard_version_id: version_id }
    assert_response :success
    assert_equal version_id, response.parsed_body["meeting_dashboard_version_id"]
  end

  test "draft lists imported new_tasks even when client date predates UTC created_at" do
    nt = NewTask.create!(
      sector_division: "S",
      description: "Imported edge",
      original_date: Time.current,
      review_date: Time.current,
      responsibility: "R",
      editor: @editor,
      status: :draft
    )
    nt.update_column(:created_at, Time.utc(2030, 6, 15, 8, 0, 0))

    get "/meeting_dashboard/draft", headers: @auth, params: { date: "2030-06-14" }
    assert_response :success
    ids = response.parsed_body["active"].map { |t| t["id"] }
    assert_includes ids, nt.id
  end

  test "import approve then draft returns that task" do
    payload = {
      task: { sn: 9, sector_division: "IFD", description: "After import", responsibility: "All JS" },
      nodes: [
        {
          "id" => "n1",
          "parent_id" => nil,
          "content" => "<p>x</p>",
          "level" => 1,
          "list_style" => "decimal",
          "node_type" => "rich_text",
          "position" => 1
        }
      ]
    }
    post "/imports/dashboard_html/approve",
         params: payload,
         headers: @auth,
         as: :json
    assert_response :success
    task_id = response.parsed_body["task_id"]

    get "/meeting_dashboard/draft", headers: @auth, params: { date: Date.current }
    assert_response :success
    ids = response.parsed_body["active"].map { |t| t["id"] }
    assert_includes ids, task_id
  end

  test "draft loads tasks with single query batch for nodes" do
    nt = NewTask.create!(
      sector_division: "S",
      description: "D",
      original_date: Time.current,
      review_date: Time.current,
      responsibility: "R",
      editor: @editor,
      status: :draft
    )
    3.times do |i|
      nt.new_action_nodes.create!(
        content: "n#{i}",
        level: 1,
        list_style: "decimal",
        node_type: "point",
        position: i + 1
      )
    end

    queries = 0
    sub = ActiveSupport::Notifications.subscribe("sql.active_record") { |_| queries += 1 }
    get "/meeting_dashboard/draft", headers: @auth, params: { date: Date.current }
    ActiveSupport::Notifications.unsubscribe(sub)

    assert_response :success
    assert_equal 1, response.parsed_body["active"].length
    assert_operator queries, :<, 25, "expected bounded SQL count for draft load, got #{queries}"
  end

  test "meeting_dashboard task nodes index returns tree and node update works" do
    nt = NewTask.create!(
      sector_division: "S",
      description: "D",
      original_date: Time.current,
      review_date: Time.current,
      responsibility: "R",
      editor: @editor,
      status: :draft
    )
    node = nt.new_action_nodes.create!(
      content: "alpha",
      level: 1,
      list_style: "decimal",
      node_type: "point",
      position: 1
    )

    get "/meeting_dashboard/tasks/#{nt.id}/nodes", headers: @auth
    assert_response :success
    tree = response.parsed_body["data"]
    assert tree.is_a?(Array)
    assert_equal node.id, tree.first["id"]
    assert_equal [], tree.first["children"]

    put "/meeting_dashboard/tasks/#{nt.id}/nodes/#{node.id}",
        params: { action_node: { reviewer_id: @editor.id } },
        headers: @auth,
        as: :json
    assert_response :success
    assert_equal @editor.id, response.parsed_body.dig("data", "reviewer_id")

    get "/meeting_dashboard/tasks/#{nt.id}/nodes/#{node.id}/review_date_extension_events",
        headers: @auth
    assert_response :success
    assert_equal [], response.parsed_body["events"]
  end

  test "meeting_dashboard node update rejects client temp id (negative)" do
    nt = NewTask.create!(
      sector_division: "S",
      description: "D",
      original_date: Time.current,
      review_date: Time.current,
      responsibility: "R",
      editor: @editor,
      status: :draft
    )

    put "/meeting_dashboard/tasks/#{nt.id}/nodes/-1",
        params: { action_node: { reviewer_id: @editor.id } },
        headers: @auth,
        as: :json
    assert_response :unprocessable_entity
    body = response.parsed_body
    assert_equal false, body["success"]
    assert body["error"].present?
  end

  test "meeting_dashboard task update persists tag_ids and draft lists tags" do
    nt = NewTask.create!(
      sector_division: "S",
      description: "D",
      original_date: Time.current,
      review_date: Time.current,
      responsibility: "R",
      editor: @editor,
      status: :draft
    )
    tag = Tag.create!(name: "MeetingFlowTag-#{SecureRandom.hex(4)}")

    put "/meeting_dashboard/tasks/#{nt.id}",
        params: {
          task: {
            sector_division: nt.sector_division,
            description: nt.description,
            responsibility: nt.responsibility,
            original_date: nt.original_date.to_date,
            review_date: nt.review_date.to_date,
            tag_ids: [tag.id]
          }
        },
        headers: @auth,
        as: :json
    assert_response :success
    data = response.parsed_body["data"]
    assert data["tags"].is_a?(Array)
    assert_equal 1, data["tags"].length
    assert_equal tag.id, data["tags"].first["id"]
    assert_equal tag.name, data["tags"].first["name"]

    get "/meeting_dashboard/draft", headers: @auth, params: { date: Date.current }
    assert_response :success
    active = response.parsed_body["active"]
    row = active.find { |t| t["id"] == nt.id }
    assert row, "expected task in active"
    assert_equal 1, row["tags"].length
    assert_equal tag.id, row["tags"].first["id"]
    assert_equal tag.name, row["tags"].first["name"]
  end

  test "draft_editor_overlay comment_nodes assignment and comments after publish" do
    nt = NewTask.create!(
      sector_division: "S",
      description: "D",
      original_date: Time.current,
      review_date: Time.current,
      responsibility: "R",
      editor: @editor,
      status: :draft
    )
    node = nt.new_action_nodes.create!(
      content: "body",
      level: 1,
      list_style: "decimal",
      node_type: "point",
      position: 1
    )
    stable = node.stable_node_id
    assert stable.present?

    reviewer = build_user(role: :reviewer, first_name: "Rev", last_name: "Viewer")
    meeting_day = Date.current

    post "/meeting_dashboard/publish",
         params: { target_meeting_date: meeting_day.to_s },
         headers: @auth,
         as: :json
    assert_response :success
    version_id = response.parsed_body["new_dashboard_version_id"]

    get "/meeting_dashboard/draft_editor_overlay",
        headers: @auth,
        params: { new_dashboard_version_id: version_id }
    assert_response :success
    overlay = response.parsed_body
    assert_equal version_id, overlay["new_dashboard_version_id"]
    assert_equal 0, overlay["nodes"][stable]["comment_count"]

    post "/meeting_dashboard/assignments",
         params: {
           new_dashboard_version_id: version_id,
           stable_node_id: stable,
           user_id: reviewer.id
         },
         headers: @auth,
         as: :json
    assert_response :success
    assert_equal reviewer.id, response.parsed_body.dig("assignment", "user_id")

    post "/meeting_dashboard/dashboard_node_comments",
         params: {
           new_dashboard_version_id: version_id,
           stable_node_id: stable,
           body: "Please revise"
         },
         headers: @auth,
         as: :json
    assert_response :success

    get "/meeting_dashboard/draft_editor_overlay",
        headers: @auth,
        params: { new_dashboard_version_id: version_id }
    assert_response :success
    assert_equal 1, response.parsed_body["nodes"][stable]["comment_count"]

    get "/meeting_dashboard/comment_nodes",
        headers: @auth,
        params: { new_dashboard_version_id: version_id }
    assert_response :success
    nodes = response.parsed_body["nodes"]
    assert_equal 1, nodes.length
    assert_equal stable, nodes.first["stable_node_id"]

    get "/meeting_dashboard/dashboard_node_comments",
        headers: @auth,
        params: { new_dashboard_version_id: version_id, stable_node_id: stable }
    assert_response :success
    assert_equal 1, response.parsed_body["comments"].length

    assign_id = NewDashboardAssignment.find_by!(new_dashboard_version_id: version_id, user_id: reviewer.id).id
    delete "/meeting_dashboard/assignments/#{assign_id}", headers: @auth
    assert_response :success
  end

  test "reviewer can read draft_editor_overlay and comment_nodes but cannot create assignments" do
    nt = NewTask.create!(
      sector_division: "S",
      description: "D",
      original_date: Time.current,
      review_date: Time.current,
      responsibility: "R",
      editor: @editor,
      status: :draft
    )
    node = nt.new_action_nodes.create!(
      content: "body",
      level: 1,
      list_style: "decimal",
      node_type: "point",
      position: 1
    )
    stable = node.stable_node_id

    post "/meeting_dashboard/publish",
         params: { target_meeting_date: Date.current.to_s },
         headers: @auth,
         as: :json
    assert_response :success
    version_id = response.parsed_body["new_dashboard_version_id"]

    reviewer = build_user(role: :reviewer, first_name: "Rev", last_name: "Two")
    post "/signin",
         params: { email: reviewer.email, password: "Password!23" },
         as: :json
    assert_response :success
    rev_access = response.parsed_body["access"]
    rev_auth = { "Authorization" => "Bearer #{rev_access}" }

    get "/meeting_dashboard/draft_editor_overlay",
        headers: rev_auth,
        params: { new_dashboard_version_id: version_id }
    assert_response :success
    assert_equal version_id, response.parsed_body["new_dashboard_version_id"]

    get "/meeting_dashboard/comment_nodes",
        headers: rev_auth,
        params: { new_dashboard_version_id: version_id }
    assert_response :success

    post "/meeting_dashboard/assignments",
         params: {
           new_dashboard_version_id: version_id,
           stable_node_id: stable,
           user_id: reviewer.id
         },
         headers: rev_auth,
         as: :json
    assert_response :forbidden
  end

  test "reschedule soft moves schedule to new meeting date" do
    nt = NewTask.create!(
      sector_division: "S",
      description: "D",
      original_date: Time.current,
      review_date: Time.current,
      responsibility: "R",
      editor: @editor,
      status: :draft
    )
    nt.new_action_nodes.create!(
      content: "x",
      level: 1,
      list_style: "decimal",
      node_type: "point",
      position: 1
    )
    d_from = Date.current
    d_to = d_from + 10.days

    post "/meeting_dashboard/publish",
         params: { target_meeting_date: d_from.to_s },
         headers: @auth,
         as: :json
    assert_response :success
    version_id = response.parsed_body["new_dashboard_version_id"]

    post "/meeting_dashboard/reschedule",
         params: { from_meeting_date: d_from.to_s, to_meeting_date: d_to.to_s },
         headers: @auth,
         as: :json
    assert_response :success
    assert_equal version_id, response.parsed_body["new_dashboard_version_id"]

    get "/meeting_dashboard/meeting_dates", headers: @auth
    assert_response :success
    dates = response.parsed_body["meeting_dates"].map { |r| Date.parse(r["meeting_date"].to_s) }
    assert_includes dates, d_to
    refute_includes dates, d_from
  end

  test "reset_draft restores new_task tags to last published snapshot" do
    nt = NewTask.create!(
      sector_division: "S",
      description: "Tag reset",
      original_date: Time.current,
      review_date: Time.current,
      responsibility: "R",
      editor: @editor,
      status: :draft
    )
    nt.new_action_nodes.create!(
      content: "x",
      level: 1,
      list_style: "decimal",
      node_type: "point",
      position: 1
    )
    tag_a = Tag.create!(name: "ResetTagA-#{SecureRandom.hex(4)}")
    tag_b = Tag.create!(name: "ResetTagB-#{SecureRandom.hex(4)}")

    put "/meeting_dashboard/tasks/#{nt.id}",
        params: {
          task: {
            sector_division: nt.sector_division,
            description: nt.description,
            responsibility: nt.responsibility,
            original_date: nt.original_date.to_date,
            review_date: nt.review_date.to_date,
            tag_ids: [tag_a.id]
          }
        },
        headers: @auth,
        as: :json
    assert_response :success

    post "/meeting_dashboard/publish",
         params: { target_meeting_date: Date.current.to_s },
         headers: @auth,
         as: :json
    assert_response :success

    st = NewDashboardVersion.order(published_at: :desc).first.new_dashboard_snapshot_tasks.first
    assert_equal [tag_a.id], st.published_tag_ids

    put "/meeting_dashboard/tasks/#{nt.id}",
        params: {
          task: {
            sector_division: nt.sector_division,
            description: nt.description,
            responsibility: nt.responsibility,
            original_date: nt.original_date.to_date,
            review_date: nt.review_date.to_date,
            tag_ids: [tag_a.id, tag_b.id]
          }
        },
        headers: @auth,
        as: :json
    assert_response :success

    get "/meeting_dashboard/draft", headers: @auth, params: { date: Date.current }
    assert_response :success
    row_pre = response.parsed_body["active"].find { |t| t["id"] == nt.id }
    assert_equal 2, row_pre["tags"].length

    post "/meeting_dashboard/reset_draft", headers: @auth, as: :json
    assert_response :success

    get "/meeting_dashboard/draft", headers: @auth, params: { date: Date.current }
    assert_response :success
    row_post = response.parsed_body["active"].find { |t| t["id"] == nt.id }
    assert row_post, "task still in draft"
    assert_equal 1, row_post["tags"].length
    assert_equal tag_a.id, row_post["tags"].first["id"]
  end
end
