# app/controllers/action_node_controller.rb
class ActionNodeController < ApplicationController
#   before_action :authorize_access_request!
  before_action :set_task_version
  before_action :set_action_node, only: [:show, :update, :destroy, :toggle_complete, :move_node]

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
    
    if @action_node.update(node_params)
      Rails.logger.info "✅ NODE UPDATE SUCCESS: reviewer_id=#{@action_node.reviewer_id}"
      
      # Update review dates up the tree if review_date changed
      if @action_node.saved_change_to_review_date?
        @action_node.update_review_date
        @action_node.parent&.update_review_date
        # Update task review date based on all nodes
        @task_version.task.update_review_date_from_nodes
      end
      
      render json: {
        success: true,
        data: serialize_node(@action_node)
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

  def serialize_node(node)
    {
      id: node.id,
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
      formatted_display: node.formatted_display,
      has_rich_formatting: node.has_rich_formatting?,
      reviewer_id: node.reviewer_id,
      reviewer_name: node.reviewer&.full_name,
      created_at: node.created_at,
      updated_at: node.updated_at
    }
  end

  def serialize_node_tree(tree_nodes)
    tree_nodes.map do |tree_item|
      {
        node: serialize_node(tree_item[:node]),
        children: serialize_node_tree(tree_item[:children])
      }
    end
  end
end 