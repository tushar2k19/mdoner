# app/controllers/action_node_controller.rb
class ActionNodeController < ApplicationController
  include NodeTreeSerializer
#   before_action :authorize_access_request!
  before_action :set_task_version
  before_action :set_action_node, only: [:show, :update, :destroy, :toggle_complete, :move_node,
                                          :review_date_extension_events]

  def index
    nodes = @task_version.node_tree
    render json: {
      success: true,
      data: serialize_node_tree(nodes)
    }
  end

  def show
    render json: {
      success: true,
      data: serialize_node(@action_node)
    }
  end

  # GET .../nodes/:id/review_date_extension_events — list saved delay attributions for this node (indexed query).
  def review_date_extension_events
    events = ReviewDateExtensionEvent
      .includes(:recorded_by)
      .where(action_node_id: @action_node.id)
      .order(created_at: :desc)
      .to_a

    render json: {
      success: true,
      count: events.length,
      events: events.map { |e| serialize_review_date_extension_event(e) }
    }
  end

  def create
    @action_node = @task_version.add_action_node(node_params)
    
    if @action_node.persisted?
      # Update parent review dates if necessary
      @action_node.parent&.update_review_date
      # Update task review date based on all nodes
      @task_version.task.update_review_date_from_nodes
      
      render json: {
        success: true,
        data: serialize_node(@action_node)
      }
    else
      render json: {
        success: false,
        errors: @action_node.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def update
    Rails.logger.info "🔧 UPDATING ACTION NODE: #{@action_node.id}"
    Rails.logger.info "🔧 NODE PARAMS: #{node_params.inspect}"
    Rails.logger.info "🔧 CURRENT REVIEWER_ID: #{@action_node.reviewer_id}"

    extension_parse = parse_review_date_extension_params
    if extension_parse[:error]
      return render json: {
        success: false,
        errors: [extension_parse[:error]]
      }, status: :unprocessable_entity
    end

    old_review_date = @action_node.review_date

    if @action_node.update(node_params)
      Rails.logger.info "✅ NODE UPDATE SUCCESS: reviewer_id=#{@action_node.reviewer_id}"

      # Update review dates up the tree if review_date changed
      if @action_node.saved_change_to_review_date?
        @action_node.update_review_date
        @action_node.parent&.update_review_date
        # Update task review date based on all nodes
        @task_version.task.update_review_date_from_nodes
        try_record_review_date_extension_event!(old_review_date, extension_parse[:payload])
      end

      render json: {
        success: true,
        data: serialize_node(@action_node.reload)
      }
    else
      Rails.logger.error "❌ NODE UPDATE FAILED: #{@action_node.errors.full_messages}"
      render json: {
        success: false,
        errors: @action_node.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  def destroy
    if @action_node.destroy
      # Update parent review dates after deletion
      parent = @action_node.parent
      parent&.update_review_date
      # Update task review date after node deletion
      @task_version.task.update_review_date_from_nodes
      
      render json: { success: true }
    else
      render json: {
        success: false,
        error: 'Failed to delete node'
      }, status: :unprocessable_entity
    end
  end

  # Add a point at the same level
  def add_point
    parent = params[:parent_id] ? @task_version.all_action_nodes.find(params[:parent_id]) : nil
    level = parent ? parent.level : (params[:level] || 1).to_i
    
    @action_node = @task_version.add_action_node(
      content: params[:content],
      level: level,
      list_style: params[:list_style] || @task_version.determine_list_style_for_level(level),
      node_type: params[:node_type] || 'point',
      parent: parent,
      review_date: params[:review_date]
    )
    
    if @action_node.persisted?
      render json: {
        success: true,
        data: serialize_node(@action_node)
      }
    else
      render json: {
        success: false,
        errors: @action_node.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # Add a subpoint (next level)
  def add_subpoint
    parent_node = @task_version.all_action_nodes.find(params[:parent_id])
    
    @action_node = @task_version.add_subpoint_to_node(
      parent_node,
      content: params[:content],
      list_style: params[:list_style],
      review_date: params[:review_date]
    )
    
    if @action_node.persisted?
      render json: {
        success: true,
        data: serialize_node(@action_node)
      }
    else
      render json: {
        success: false,
        errors: @action_node.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # Toggle completion status
  def toggle_complete
    @action_node.update(completed: !@action_node.completed)
    @action_node.update_completion_status # Update parent completion status
    
    render json: {
      success: true,
      data: serialize_node(@action_node)
    }
  end

  # Move node to different position/level
  def move_node
    new_level = params[:new_level].to_i
    new_parent_id = params[:new_parent_id]
    new_position = params[:new_position].to_i
    
    if @action_node.can_change_level?(new_level)
      new_parent = new_parent_id ? @task_version.all_action_nodes.find(new_parent_id) : nil
      
      @action_node.update!(
        level: new_level,
        parent: new_parent,
        position: new_position
      )
      
      render json: {
        success: true,
        data: serialize_node(@action_node)
      }
    else
      render json: {
        success: false,
        error: 'Invalid level change'
      }, status: :unprocessable_entity
    end
  end

  # Bulk operations
  def bulk_update
    node_ids = params[:node_ids]
    updates = params[:updates]
    
    nodes = @task_version.all_action_nodes.where(id: node_ids)
    
    ActiveRecord::Base.transaction do
      nodes.each do |node|
        node.update!(updates)
      end
    end
    
    render json: { success: true }
  rescue ActiveRecord::RecordInvalid => e
    render json: {
      success: false,
      error: e.message
    }, status: :unprocessable_entity
  end

  # Resort nodes by review date
  def resort_by_date
    @task_version.update_and_resort_nodes
    
    render json: {
      success: true,
      data: serialize_node_tree(@task_version.node_tree)
    }
  end

  private

  def set_task_version
    @task_version = TaskVersion.find(params[:task_version_id])
  end

  def set_action_node
    @action_node = @task_version.all_action_nodes.find(params[:id])
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
    reason = permitted['reason'].to_s.strip
    explanation = permitted['explanation'].to_s

    if reason.blank?
      return { error: 'reason is required when review_date_extension is sent' }
    end

    code = reason.downcase.tr(' ', '_')
    unless ReviewDateExtensionEvent::REASON_CODES.include?(code)
      return { error: "invalid reason (allowed: #{ReviewDateExtensionEvent::REASON_CODES.join(', ')})" }
    end

    {
      payload: {
        reason: code,
        explanation: explanation.truncate(ReviewDateExtensionEvent::MAX_EXPLANATION_LENGTH)
      }
    }
  end

  def serialize_review_date_extension_event(event)
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

  def try_record_review_date_extension_event!(old_review_date, extension_payload)
    return if extension_payload.blank?

    old_d = old_review_date&.to_date
    new_d = @action_node.review_date&.to_date
    return unless old_d && new_d && new_d > old_d

    event = ReviewDateExtensionEvent.new(
      task: @task_version.task,
      task_version: @task_version,
      action_node: @action_node,
      stable_node_id: @action_node.stable_node_id,
      previous_review_date: old_d,
      new_review_date: new_d,
      reason: extension_payload[:reason],
      explanation: extension_payload[:explanation].presence,
      recorded_by: current_user
    )

    return if event.save

    Rails.logger.warn(
      "[ReviewDateExtensionEvent] skipped: #{event.errors.full_messages.join(', ')} " \
      "(action_node_id=#{@action_node.id})"
    )
  end

  def serialize_node(node)
    # Fallback for single node serialization
    serialize_node_with_precalculated(node, node.display_counter, node.formatted_display)
  end

  def serialize_node_with_precalculated(node, display_counter, formatted_display)
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
      display_counter: display_counter,
      formatted_display: formatted_display,
      has_rich_formatting: node.has_rich_formatting?,
      reviewer_id: node.reviewer_id,
      reviewer_name: node.reviewer&.full_name,
      created_at: node.created_at,
      updated_at: node.updated_at
    }
  end

  def serialize_node_tree(tree_nodes)
    tree_with_counters = calculate_display_counters(tree_nodes)
    serialize_tree_with_counters(tree_with_counters)
  end

  def serialize_tree_with_counters(tree_nodes)
    tree_nodes.map do |tree_item|
      {
        node: serialize_node_with_precalculated(tree_item[:node], tree_item[:display_counter], tree_item[:formatted_display]),
        children: serialize_tree_with_counters(tree_item[:children])
      }
    end
  end
end 