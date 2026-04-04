# frozen_string_literal: true

# Incremental updates for living draft nodes (reviewer, review_date, etc.).
# Parallels ActionNodeController#update / #review_date_extension_events for legacy task_versions.
class MeetingDashboard::TaskNodesController < ApplicationController
  before_action :require_meeting_dashboard!
  before_action :set_new_task
  before_action :set_new_action_node

  # GET /meeting_dashboard/tasks/:task_id/nodes/:id/review_date_extension_events
  # Legacy uses ReviewDateExtensionEvent (tasks/task_versions/action_nodes). New flow has no row yet —
  # return an empty list so the UI does not error; delay attribution for new_* can be added later.
  def review_date_extension_events
    render json: { success: true, count: 0, events: [] }
  end

  # PUT /meeting_dashboard/tasks/:task_id/nodes/:id
  # Body: { action_node: { review_date, reviewer_id, ... } } — same envelope as legacy ActionNodeController
  def update
    if @node.update(node_params)
      @new_task.update_review_date_from_nodes if @node.saved_change_to_review_date?
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
