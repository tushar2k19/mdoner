class ReviewController < ApplicationController
  include ActionNodePersister
  include NodeTreeSerializer
  # before_action :authorize_access_request!
  # Use except: (not only: [..., :remind_reviewer]) so Rails 7.1 does not require every symbol
  # in :only to exist as an action. A missing remind_reviewer method would otherwise break
  # all ReviewController actions including #show (raise_on_missing_callback_actions).
  before_action :set_review, except: [:index, :diff, :reviewer_status_breakdown]

  def index
    # Get all reviews for current user (as reviewer or editor)
    reviews = Review.joins(:task_version)
                   .where('reviews.reviewer_id = ? OR task_versions.editor_id = ?', 
                          current_user.id, current_user.id)
                   .includes(
                     {
                       task_version: [
                         :task,
                         :editor,
                         {
                           all_action_nodes: [:reviewer, :parent]
                         }
                       ]
                     },
                     :base_version,
                     :reviewer,
                     {
                       comment_trail: :comments
                     }
                   )
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
        modified_nodes: [],
        moved_nodes: []
      }
      baseline_nodes = []
    else
      # Get diff data between base version and current version
      diff_data = @review.task_version.diff_with(@review.base_version)
      
      # Prepare baseline nodes using existing serializer
      base_tree_nodes = @review.base_version.node_tree
      base_tree_with_counters = calculate_display_counters(base_tree_nodes)
      # Pass empty diff_data so they don't get diff coloring applied incorrectly
      baseline_nodes = serialize_node_tree_with_diff(base_tree_with_counters, {})
    end
    
    # Get nodes with diff status applied
    tree_nodes = @review.task_version.node_tree
    tree_with_counters = calculate_display_counters(tree_nodes)
    
    # Get comment trail for this review
    comment_trail = @review.comment_trail
    
    render json: {
      success: true,
      data: {
        review: serialize_review(@review),
        task: serialize_task(@review.task_version.task),
        nodes: serialize_node_tree_with_diff(tree_with_counters, diff_data),
        baseline_nodes: baseline_nodes,
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
        NotificationDispatcher.new.deliver(
          @review.reviewer.id,
          'editor_changes',
          "Editor has made changes to task '#{@review.task_version.task.description}' - please re-review",
          task_id: @review.task_version.task_id,
          review_id: @review.id
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
      Rails.logger.info "🔧 APPROVAL DEBUG: Starting approval for review #{@review.id}"
      Rails.logger.info "🔧 Review assigned_node_ids: #{@review.assigned_node_ids.inspect}"
      Rails.logger.info "🔧 Task version status before: #{@review.task_version.status}"
      
      # Update review status
      @review.update!(status: 'approved')
      
      Rails.logger.info "🔧 Review status updated to: #{@review.status}"
      Rails.logger.info "🔧 Task version status after: #{@review.task_version.status}"
      
      # Check if all reviews for this task version are now approved
      task_version = @review.task_version
      all_reviews = Review.where(task_version: task_version, status: ['pending', 'approved', 'changes_requested'])
      
      Rails.logger.info "🔧 Total reviews for task version: #{all_reviews.count}"
      Rails.logger.info "🔧 Review statuses: #{all_reviews.pluck(:id, :status).inspect}"
      
      if all_reviews.all? { |review| review.status == 'approved' }
        # All reviews approved - mark task as approved
        task_version.update!(status: 'approved')
        task_version.task.update!(current_version: task_version)
        task_version.task.update!(status: 'approved')
        
        # Create notification for editor
        NotificationDispatcher.new.deliver(
          task_version.editor.id,
          'task_approved',
          "Your task '#{task_version.task.description}' has been fully approved by all reviewers",
          task_id: task_version.task_id,
          review_id: @review.id
        )
        
        message = 'Review approved - Task fully approved by all reviewers'
      else
        # Some reviews still pending - task remains under review
        pending_count = all_reviews.count { |review| review.status == 'pending' }
        
        # Create notification for editor about partial approval
        NotificationDispatcher.new.deliver(
          task_version.editor.id,
          'partial_approval',
          "Your task '#{task_version.task.description}' has been partially approved (#{pending_count} reviews pending)",
          task_id: task_version.task_id,
          review_id: nil
        )
        
        message = "Review approved - #{pending_count} review(s) still pending"
      end
      
      render json: {
        success: true,
        message: message,
        all_reviews_approved: all_reviews.all? { |review| review.status == 'approved' }
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
      NotificationDispatcher.new.deliver(
        @review.task_version.editor.id,
        'changes_requested',
        "Changes requested for task '#{@review.task_version.task.description}'",
        task_id: @review.task_version.task_id,
        review_id: @review.id
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
      NotificationDispatcher.new.deliver(
        new_reviewer.id,
        'review_forwarded',
        "Review forwarded to you for task '#{@review.task_version.task.description}'",
        task_id: @review.task_version.task_id,
        review_id: new_review.id
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

  # Editor nudges a pending reviewer (same task version cycle only).
  def remind_reviewer
    task = @review.task_version.task

    unless task.editor_id == current_user.id
      render json: { success: false, error: 'Forbidden' }, status: :forbidden
      return
    end

    unless @review.task_version_id == task.current_version_id
      render json: { success: false, error: 'Review is not for the current task version' }, status: :unprocessable_entity
      return
    end

    unless @review.pending?
      render json: { success: false, error: 'Reminders are only sent for pending reviews' }, status: :unprocessable_entity
      return
    end

    if @review.last_reminder_sent_at.present? && @review.last_reminder_sent_at > 10.minutes.ago
      render json: {
        success: false,
        error: 'Please wait before sending another reminder',
        retry_after_seconds: (600 - (Time.current - @review.last_reminder_sent_at)).to_i.clamp(0, 600)
      }, status: :too_many_requests
      return
    end

    @review.update!(last_reminder_sent_at: Time.current)

    NotificationDispatcher.new.deliver(
      @review.reviewer.id,
      :review_reminder,
      "Reminder: your review is still pending for '#{task.description}'",
      task_id: task.id,
      review_id: @review.id
    )

    render json: {
      success: true,
      data: {
        last_reminder_sent_at: @review.last_reminder_sent_at
      }
    }
  rescue ActiveRecord::RecordInvalid => e
    render json: { success: false, error: e.message }, status: :unprocessable_entity
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

  # New endpoint for dashboard hover functionality
  def reviewer_status_breakdown
    task_version_id = params[:task_version_id]
    
    if task_version_id.present?
      task_version = TaskVersion.find(task_version_id)
      breakdown = Review.get_reviewer_status_breakdown(task_version)
      
      render json: {
        success: true,
        breakdown: breakdown
      }
    else
      render json: {
        success: false,
        error: 'task_version_id is required'
      }, status: :bad_request
    end
  end

  private

  def set_review
    @review = Review.includes(
      {
        task_version: [
          :task,
          :editor,
          {
            all_action_nodes: [:reviewer, :parent]
          }
        ]
      },
      {
        base_version: {
          all_action_nodes: [:reviewer, :parent]
        }
      },
      :reviewer,
      {
        comment_trail: :comments
      }
    ).find(params[:id])
  end

  def serialize_review(review)
    {
      id: review.id,
      status: review.status,
      summary: review.summary,
      created_at: review.created_at,
      updated_at: review.updated_at,
      reviewer_type: review.reviewer_type,
      assigned_node_ids: review.assigned_node_ids,
      is_aggregate_review: review.is_aggregate_review,
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
      reviewer_type: review.reviewer_type,
      assigned_node_ids: review.assigned_node_ids,
      is_aggregate_review: review.is_aggregate_review,
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
        node: serialize_node_with_diff(node, diff_status, tree_item[:display_counter], tree_item[:formatted_display]),
        children: serialize_node_tree_with_diff(tree_item[:children], diff_data)
      }
    end
  end

  def serialize_node_with_diff(node, diff_status, display_counter, formatted_display)
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
      diff_status: diff_status, # added, modified, deleted, unchanged
      created_at: node.created_at,
      updated_at: node.updated_at,
      reviewer_id: node.reviewer_id,
      reviewer_name: node.reviewer&.full_name # full name for review/diff UI
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
    
    # Check if node is in modified nodes
    if diff_data[:modified_nodes]&.any? { |modified_node| modified_node.id == node.id }
      return 'modified'
    end
    
    # Check if node is in moved nodes
    if diff_data[:moved_nodes]&.any? { |moved_node| moved_node.id == node.id }
      return 'moved'
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
    # Apply delta to update nodes instead of destroying and recreating
    apply_action_nodes_delta(task_version, nodes_data)
  end
end 