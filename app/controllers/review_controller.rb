class ReviewController < ApplicationController
  # before_action :authorize_access_request!
  before_action :set_review, only: [:show, :update, :approve, :reject, :forward, :comments]

  def index
    # Get all reviews for current user (as reviewer or editor)
    reviews = Review.joins(:task_version)
                   .where('reviews.reviewer_id = ? OR task_versions.editor_id = ?', 
                          current_user.id, current_user.id)
                   .includes({task_version: [:task, :editor]}, :base_version, :reviewer, {comment_trail: :comments})
                   .order(created_at: :desc)
    
    render json: {
      success: true,
      data: reviews.map { |review| serialize_review_summary(review) }
    }
  end

  def show
    # Handle case when base_version is nil (first review)
    if @review.base_version.nil?
      # For first review, mark all nodes as "added" (green)
      all_nodes = @review.task_version.all_action_nodes.to_a
      diff_data = {
        added_nodes: all_nodes,
        removed_nodes: [],
        modified_nodes: []
      }
    else
      # Get diff data between base version and current version
      diff_data = @review.task_version.diff_with(@review.base_version)
    end
    
    # Get nodes with diff status applied
    nodes_with_diff = serialize_node_tree_with_diff(@review.task_version.node_tree, diff_data)
    
    # Get comment trail for this review
    comment_trail = @review.comment_trail
    
    render json: {
      success: true,
      data: {
        review: serialize_review(@review),
        task: serialize_task(@review.task_version.task),
        nodes: serialize_node_tree_with_diff(@review.task_version.node_tree, diff_data),
        diff: diff_data,
        comment_trails: comment_trail ? [serialize_comment_trail(comment_trail)] : [],
        current_user: {
          id: current_user.id,
          role: current_user.role,
          name: current_user.full_name,
          email: current_user.email
        }
      }
    }
  end

  def update
    # Update review content (if reviewer makes edits)
    if params[:nodes_data].present?
      ActiveRecord::Base.transaction do
        # Update the task version with new node data
        update_task_version_nodes(@review.task_version, params[:nodes_data])
        
        # Update review status
        @review.update!(status: params[:status] || 'pending')
        
        render json: {
          success: true,
          data: serialize_review(@review)
        }
      end
    elsif params[:editor_changes].present?
      # Editor has made changes and wants to notify reviewer
      ActiveRecord::Base.transaction do
        # Update review status to indicate editor changes
        @review.update!(status: 'pending')
        
        # Create notification for reviewer
        Notification.create!(
          recipient: @review.reviewer,
          task: @review.task_version.task,
          review: @review,
          message: "Editor has made changes to task '#{@review.task_version.task.description}' - please re-review",
          notification_type: 'editor_changes'
        )
        
        render json: {
          success: true,
          message: 'Reviewer notified of changes'
        }
      end
    else
      render json: {
        success: false,
        error: 'No update data provided'
      }, status: :unprocessable_entity
    end
  rescue ActiveRecord::RecordInvalid => e
    render json: {
      success: false,
      error: e.message
    }, status: :unprocessable_entity
  end

  def approve
    ActiveRecord::Base.transaction do
      # Update review status
      @review.update!(status: 'approved')
      
      # Update task version status
      @review.task_version.update!(status: 'approved')
      
      # Set this as the current version of the task
      @review.task_version.task.update!(current_version: @review.task_version)
      
      # Update task status to approved
      @review.task_version.task.update!(status: 'approved')
      
      # Create notification for editor
      Notification.create!(
        recipient: @review.task_version.editor,
        task: @review.task_version.task,
        review: @review,
        message: "Your task '#{@review.task_version.task.description}' has been approved",
        notification_type: 'task_approved'
      )
      
      render json: {
        success: true,
        message: 'Review approved successfully'
      }
    end
  rescue ActiveRecord::RecordInvalid => e
    render json: {
      success: false,
      error: e.message
    }, status: :unprocessable_entity
  end

  def reject
    ActiveRecord::Base.transaction do
      # Update review status
      @review.update!(status: 'changes_requested')
      
      # Update task version status back to draft
      @review.task_version.update!(status: 'draft')
      
      # Create notification for editor
      Notification.create!(
        recipient: @review.task_version.editor,
        task: @review.task_version.task,
        review: @review,
        message: "Changes requested for task '#{@review.task_version.task.description}'",
        notification_type: 'changes_requested'
      )
      
      render json: {
        success: true,
        message: 'Changes requested successfully'
      }
    end
  rescue ActiveRecord::RecordInvalid => e
    render json: {
      success: false,
      error: e.message
    }, status: :unprocessable_entity
  end

  def forward
    new_reviewer_id = params[:new_reviewer_id]
    new_reviewer = User.find(new_reviewer_id)
    
    ActiveRecord::Base.transaction do
      # Update current review status
      @review.update!(status: 'forwarded')
      
      # Create new review for the new reviewer
      new_review = Review.create!(
        task_version: @review.task_version,
        base_version: @review.base_version,
        reviewer: new_reviewer,
        status: 'pending'
      )
      
      # Create notifications
      Notification.create!(
        recipient: new_reviewer,
        task: @review.task_version.task,
        review: new_review,
        message: "Review forwarded to you for task '#{@review.task_version.task.description}'",
        notification_type: 'review_forwarded'
      )
      
      render json: {
        success: true,
        message: 'Review forwarded successfully',
        data: serialize_review(new_review)
      }
    end
  rescue ActiveRecord::RecordNotFound
    render json: {
      success: false,
      error: 'Reviewer not found'
    }, status: :not_found
  rescue ActiveRecord::RecordInvalid => e
    render json: {
      success: false,
      error: e.message
    }, status: :unprocessable_entity
  end

  def diff
    # Get detailed diff between any two versions
    base_version_id = params[:base_version_id]
    current_version_id = params[:current_version_id]
    
    base_version = TaskVersion.find(base_version_id)
    current_version = TaskVersion.find(current_version_id)
    
    diff_data = {
      added_nodes: current_version.all_action_nodes.where.not(
        id: base_version.all_action_nodes.select(:id)
      ),
      removed_nodes: base_version.all_action_nodes.where.not(
        id: current_version.all_action_nodes.select(:id)
      ),
      modified_nodes: [] # This would need more complex logic
    }
    
    render json: {
      success: true,
      diff: diff_data
    }
  end

  # New method: Get comments for a review
  def comments
    # Ensure the review has a comment trail
    trail = @review.comment_trail || @review.create_comment_trail!
    
    comments = trail.comments.includes(:user, :action_node).order(created_at: :asc).map do |comment|
      {
        id: comment.id,
        content: comment.content,
        user_name: comment.user.full_name,
        user_id: comment.user.id,
        created_at: comment.created_at,
        resolved: comment.resolved,
        action_node_id: comment.action_node_id,
        references_node: comment.references_node?,
        referenced_node: comment.references_node? ? {
          content: comment.referenced_node_content,
          counter: comment.referenced_node_counter,
          exists: comment.referenced_node_exists?
        } : nil
      }
    end

    render json: {
      success: true,
      comments: comments
    }
  end

  private

  def set_review
    @review = Review.find(params[:id])
  end

  def serialize_review(review)
    {
      id: review.id,
      status: review.status,
      summary: review.summary,
      created_at: review.created_at,
      updated_at: review.updated_at,
      reviewer: {
        id: review.reviewer.id,
        name: review.reviewer.full_name,
        email: review.reviewer.email
      },
      task_version: serialize_version_summary(review.task_version),
      base_version: serialize_version_summary(review.base_version)
    }
  end

  def serialize_review_summary(review)
    {
      id: review.id,
      status: review.status,
      created_at: review.created_at,
      task: {
        id: review.task_version.task.id,
        description: review.task_version.task.description,
        sector_division: review.task_version.task.sector_division,
        responsibility: review.task_version.task.responsibility,
        review_date: review.task_version.task.review_date,
        original_date: review.task_version.task.original_date,
        status: review.task_version.task.status
      },
      reviewer: {
        id: review.reviewer.id,
        name: review.reviewer.full_name,
        email: review.reviewer.email
      },
      task_version: {
        id: review.task_version.id,
        version_number: review.task_version.version_number,
        status: review.task_version.status,
        editor_id: review.task_version.editor_id,
        editor_name: review.task_version.editor.full_name
      },
      comment_trail: review.comment_trail ? {
        id: review.comment_trail.id,
        comments: review.comment_trail.comments.map { |comment| serialize_comment(comment) }
      } : nil
    }
  end

  def serialize_task(task)
    {
      id: task.id,
      sector_division: task.sector_division,
      description: task.description,
      responsibility: task.responsibility,
      original_date: task.original_date,
      review_date: task.review_date,
      status: task.status,
      current_version_id: task.current_version_id
    }
  end

  def serialize_version_summary(version)
    return nil unless version
    
    {
      id: version.id,
      version_number: version.version_number,
      status: version.status,
      created_at: version.created_at,
      editor_name: version.editor.full_name,
      editor_id: version.editor.id
    }
  end

  def serialize_node_tree_with_diff(tree_nodes, diff_data)
    tree_nodes.map do |tree_item|
      node = tree_item[:node]
      
      # Determine diff status for this node
      diff_status = get_node_diff_status(node, diff_data)
      
      {
        node: serialize_node_with_diff(node, diff_status),
        children: serialize_node_tree_with_diff(tree_item[:children], diff_data)
      }
    end
  end

  def serialize_node_with_diff(node, diff_status)
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
      diff_status: diff_status, # added, modified, deleted, unchanged
      created_at: node.created_at,
      updated_at: node.updated_at,
      reviewer_id: node.reviewer_id,
      reviewer_name: node.reviewer&.first_name # Include reviewer name if reviewer exists 
    }
  end

  def get_node_diff_status(node, diff_data)
    # Check if node is in added nodes
    if diff_data[:added_nodes]&.any? { |added_node| added_node.id == node.id }
      return 'added'
    end
    
    # Check if node is in removed nodes
    if diff_data[:removed_nodes]&.any? { |removed_node| removed_node.id == node.id }
      return 'deleted'
    end
    
    # Check if node is in modified nodes (now just an array of nodes)
    if diff_data[:modified_nodes]&.any? { |modified_node| modified_node.id == node.id }
      return 'modified'
    end
    
    # Default to unchanged
    'unchanged'
  end

  def serialize_comment_trail(trail)
    {
      id: trail.id,
      review_id: trail.review_id,
      created_at: trail.created_at,
      comments: trail.comments.map { |comment| serialize_comment(comment) }
    }
  end

  def serialize_comment(comment)
    {
      id: comment.id,
      content: comment.content,
      review_date: comment.review_date,
      resolved: comment.resolved,
      user_name: comment.user.full_name,
      created_at: comment.created_at,
      action_node_id: comment.action_node_id
    }
  end

  def update_task_version_nodes(task_version, nodes_data)
    # Clear existing nodes
    task_version.all_action_nodes.destroy_all
    
    # Create new nodes from the updated data
    create_action_nodes_for_version(task_version, nodes_data)
  end

  def create_action_nodes_for_version(version, nodes_data)
    # Handle both flat and hierarchical node structures
    flat_nodes = flatten_node_structure(nodes_data)
    
    # Sort by level to ensure parents are created before children
    sorted_nodes = flat_nodes.sort_by { |node| [node['level'] || 1, node['position'] || 0] }
    
    # Keep track of created nodes for parent-child relationships
    node_id_mapping = {}
    
    sorted_nodes.each do |node_data|
      # Skip nodes without content
      next if node_data['content'].blank?
      
      # Find parent if specified
      parent_node = nil
      if node_data['parent_id'] && node_id_mapping[node_data['parent_id']]
        parent_node = node_id_mapping[node_data['parent_id']]
      end
      
      # Create the node
      new_node = version.all_action_nodes.create!(
        content: node_data['content'],
        level: node_data['level'] || 1,
        list_style: node_data['list_style'] || 'decimal',
        node_type: node_data['node_type'] || 'rich_text',
        position: node_data['position'] || 1,
        review_date: node_data['review_date'],
        completed: node_data['completed'] || false,
        parent: parent_node,
        reviewer_id: node_data['reviewer_id'] # Preserve reviewer_id when creating nodes
      )
      
      # Store mapping for children
      if node_data['id']
        node_id_mapping[node_data['id']] = new_node
      end
    end
  end

  def flatten_node_structure(nodes_data)
    # If nodes_data is already flat, return as is
    return nodes_data unless nodes_data.first&.key?('children')
    
    # Otherwise, flatten the hierarchical structure
    result = []
    
    def flatten_recursive(nodes, result)
      nodes.each do |node|
        # Add the node itself (without children)
        node_copy = node.except('children')
        result << node_copy
        
        # Recursively add children
        if node['children'] && node['children'].any?
          flatten_recursive(node['children'], result)
        end
      end
    end
    
    flatten_recursive(nodes_data, result)
    result
  end
end 