# frozen_string_literal: true

# Incremental updates for living draft nodes (reviewer, review_date, etc.).
# Parallels ActionNodeController#update / #review_date_extension_events for legacy task_versions.
#
# == JSON API (for New Task Modal / meeting UI) — Prompt 4
#
# PUT /meeting_dashboard/tasks/:task_id/nodes/:id
# Body:
#   {
#     "action_node": { "review_date": "...", "reviewer_id": 1, ... },
#     "review_date_extension": { "reason": "operational", "explanation": "optional text" }   // optional
#   }
# - +review_date_extension+ may be omitted or null/empty: update proceeds; an audit row is created only
#   when extension payload is present AND the stored review_date calendar day moves strictly later
#   (same semantics as legacy try_record_review_date_extension_event!).
# - +reason+ (required if review_date_extension is sent): one of
#   operational, financial, weather, misc, technical, other (spaces become underscores).
# - +explanation+ optional; max length ReviewDateExtensionCodes::MAX_EXPLANATION_LENGTH.
# - If review_date_extension is present but invalid (e.g. bad reason): 422
#   { "success": false, "errors": ["..."] } — no partial update.
#
# GET /meeting_dashboard/tasks/:task_id/nodes/:id/review_date_extension_events
# Response: { "success": true, "count": N, "events": [ { id, previous_review_date, new_review_date,
#   reason, explanation, recorded_at, recorded_by: { id, full_name } } ] }
# Dates in events are ISO8601 date strings.
#
# == Non-goal
# Bulk task save via MeetingDashboard::TasksController#sync_nodes can change node review_date without
# per-node delay payloads; no NewReviewDateExtensionEvent rows are written on that path until API extends.
#
# Authorization: same as before this feature — JWT + meeting_dashboard enabled; no extra editor gate here.
class MeetingDashboard::TaskNodesController < ApplicationController
  before_action :require_meeting_dashboard!
  before_action :set_new_task
  before_action :set_new_action_node

  def review_date_extension_events
    events = NewReviewDateExtensionEvent
      .includes(:recorded_by)
      .where(new_action_node_id: @node.id)
      .order(created_at: :desc)
      .to_a

    render json: {
      success: true,
      count: events.length,
      events: events.map { |e| serialize_new_review_date_extension_event(e) }
    }
  end

  def update
    extension_parse = parse_review_date_extension_params
    if extension_parse[:error]
      return render json: {
        success: false,
        errors: [extension_parse[:error]]
      }, status: :unprocessable_entity
    end

    old_review_date = @node.review_date

    if @node.update(node_params)
      if @node.saved_change_to_review_date?
        @new_task.update_review_date_from_nodes
        try_record_new_review_date_extension_event!(old_review_date, extension_parse[:payload])
      end
      render json: {
        success: true,
        data: serialize_meeting_node(@node.reload)
      }
    else
      render json: { success: false, errors: @node.errors.full_messages }, status: :unprocessable_entity
    end
  end

  private

  def require_meeting_dashboard!
    return if Rails.configuration.x.meeting_dashboard_enabled

    render json: { error: "Meeting dashboard disabled" }, status: :not_found
  end

  def set_new_task
    @new_task = NewTask.find(params[:task_id])
  end

  def set_new_action_node
    id = params[:id].to_i
    if id <= 0
      render(
        json: {
          success: false,
          error: "Invalid node id (#{params[:id].inspect}). New rows exist only in the editor until the task is saved; save the task to get database ids, then assign reviewers or set dates per node."
        },
        status: :unprocessable_entity
      )
      return
    end

    @node = @new_task.new_action_nodes.find_by(id: id)
    return if @node

    render json: { success: false, error: "Action node not found" }, status: :not_found
    return
  end

  def node_params
    params.require(:action_node).permit(
      :content, :level, :list_style, :node_type, :parent_id,
      :review_date, :completed, :position, :reviewer_id
    )
  end

  # Optional: { reason: 'operational', explanation: '...' } — only stored when review date moves later.
  def parse_review_date_extension_params
    raw = params[:review_date_extension]
    return { payload: nil } if raw.blank?

    permitted = raw.permit(:reason, :explanation).to_h
    reason = permitted["reason"].to_s.strip
    explanation = permitted["explanation"].to_s

    if reason.blank?
      return { error: "reason is required when review_date_extension is sent" }
    end

    code = reason.downcase.tr(" ", "_")
    unless ReviewDateExtensionCodes::REASON_CODES.include?(code)
      return { error: "invalid reason (allowed: #{ReviewDateExtensionCodes::REASON_CODES.join(', ')})" }
    end

    {
      payload: {
        reason: code,
        explanation: explanation.truncate(ReviewDateExtensionCodes::MAX_EXPLANATION_LENGTH)
      }
    }
  end

  def serialize_new_review_date_extension_event(event)
    {
      id: event.id,
      previous_review_date: event.previous_review_date&.iso8601,
      new_review_date: event.new_review_date&.iso8601,
      reason: event.reason,
      explanation: event.explanation,
      recorded_at: event.created_at.iso8601,
      recorded_by: {
        id: event.recorded_by_id,
        full_name: event.recorded_by&.full_name
      }
    }
  end

  def try_record_new_review_date_extension_event!(old_review_date, extension_payload)
    return if extension_payload.blank?

    old_d = old_review_date&.to_date
    new_d = @node.review_date&.to_date
    return unless old_d && new_d && new_d > old_d

    event = NewReviewDateExtensionEvent.new(
      new_task: @new_task,
      new_action_node: @node,
      stable_node_id: @node.stable_node_id,
      previous_review_date: old_d,
      new_review_date: new_d,
      reason: extension_payload[:reason],
      explanation: extension_payload[:explanation].presence,
      recorded_by: current_user
    )

    return if event.save

    Rails.logger.warn(
      "[NewReviewDateExtensionEvent] skipped: #{event.errors.full_messages.join(', ')} " \
      "(new_action_node_id=#{@node.id})"
    )
  end

  def serialize_meeting_node(node)
    reviewer = node.reviewer
    {
      id: node.id,
      stable_node_id: node.stable_node_id,
      content: node.content,
      html_content: node.html_content,
      level: node.level,
      list_style: node.list_style,
      node_type: node.node_type,
      position: node.position,
      review_date: node.review_date,
      completed: node.completed,
      parent_id: node.parent_id,
      display_counter: node.display_counter,
      formatted_display: nil,
      has_rich_formatting: %w[rich_text table].include?(node.node_type) || node.content.to_s.match?(/<[^>]+>/),
      reviewer_id: node.reviewer_id,
      reviewer_name: reviewer&.full_name,
      created_at: node.created_at,
      updated_at: node.updated_at
    }
  end
end
