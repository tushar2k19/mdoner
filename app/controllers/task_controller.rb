class TaskController < ApplicationController
  # before_action :authorize_access_request!
  before_action :set_task, only: [
    :update,
    :destroy,
    :send_for_review,
    :approve,
  ]
  def index
    date = params[:date] ? Date.parse(params[:date]) : Date.today
    
    # Get active tasks based on user role
    active_tasks = case current_user.role
                   when 'editor'
                     # Editors see all active tasks with their current versions
                     Task.includes(:editor, :current_version)
                         .where.not(status: 'completed')
                         .where('DATE(created_at) <= ?', date)
                   when 'reviewer'
                     # Reviewers see tasks where they have pending or active reviews
                     task_ids = Review.joins(:task_version)
                                     .where(reviewer: current_user)
                                     .where.not(status: 'approved')
                                     .pluck('task_versions.task_id')
                                     .uniq
                     
                     Task.includes(:editor, :current_version)
                         .where(id: task_ids)
                         .where.not(status: 'completed')
                         .where('DATE(created_at) <= ?', date)
                   else
                     Task.none
                   end

    # No sorting - keep tasks in natural order (as saved)
    sorted_active_tasks = active_tasks

    completed_tasks = case current_user.role
                      when 'editor'
                        Task.includes(:editor, :current_version)
                            .where(status: 'completed')
                            .where('DATE(completed_at) <= ?', date)
                      when 'reviewer'
                        # Completed tasks where reviewer was involved
                        task_ids = Review.joins(:task_version)
                                        .where(reviewer: current_user, status: 'approved')
                                        .pluck('task_versions.task_id')
                                        .uniq
                        
                        Task.includes(:editor, :current_version)
                            .where(id: task_ids, status: 'completed')
                            .where('DATE(completed_at) <= ?', date)
                      else
                        Task.none
                      end.order(completed_at: :desc)

    render json: {
      active: serialize_tasks_with_versions(sorted_active_tasks),
      completed: serialize_tasks_with_versions(completed_tasks)
    }
  end

  def approved_tasks
    date = params[:date] ? Date.parse(params[:date]) : Date.today
    
    # Get tasks with approved current versions (for Final Dashboard)
    approved_tasks = case current_user.role
                     when 'editor'
                       Task.includes(:editor, :current_version)
                           .where(status: :approved)
                           .where('DATE(updated_at) <= ?', date)
                           .where(completed_at: nil)
                     when 'reviewer'
                       # Tasks where this reviewer approved the current version
                       task_ids = Review.joins(:task_version)
                                       .where(reviewer: current_user, status: 'approved')
                                       .joins('JOIN tasks ON tasks.current_version_id = task_versions.id')
                                       .pluck('task_versions.task_id')
                                       .uniq
                       
                       Task.includes(:editor, :current_version)
                           .where(id: task_ids, status: :approved)
                           .where('DATE(updated_at) <= ?', date)
                           .where(completed_at: nil)
                     else
                       Task.none
                     end

    # No sorting - keep tasks in natural order (as saved)
    sorted_tasks = approved_tasks

    render json: { 
      tasks: serialize_tasks_with_versions(sorted_tasks)
    }
  end

  def completed_tasks
    date = params[:date] ? Date.parse(params[:date]) : Date.today
    base_query = Task.includes(:editor, :current_version)
                     .where.not(completed_at: nil)
                     .where('DATE(completed_at) <= ?', date)

    tasks = case current_user.role
            when 'editor'
              base_query
            when 'reviewer'
              # Get tasks where this user was a reviewer for any version
              task_ids = Review.joins(:task_version)
                              .where(reviewer: current_user)
                              .pluck('task_versions.task_id')
                              .uniq
              base_query.where(id: task_ids)
            else
              Task.none
            end.order(completed_at: :desc)

    render json: { tasks: serialize_tasks_with_versions(tasks) }
  end

  def create
    ActiveRecord::Base.transaction do
      # Create the task
      task = current_user.created_tasks.build(task_params_without_action)
      
      if task.save
        # Create initial version
        initial_version = task.versions.create!(
          editor: current_user,
          version_number: 1,
          status: 'draft'
        )
        
        # Set as current version
        task.update!(current_version: initial_version)
        
        # Create action nodes if provided
        if params[:action_nodes].present?
          create_action_nodes_for_version(initial_version, params[:action_nodes])
        elsif params[:task][:action_to_be_taken].present?
          # Fallback: create a single paragraph node from HTML content
          initial_version.add_action_node(
            content: strip_html_tags(params[:task][:action_to_be_taken]),
            level: 1,
            list_style: 'paragraph',
            node_type: 'paragraph'
          )
        end
        
        # Update task's review_date based on node dates
        task.update_review_date_from_nodes
        
        render json: { 
          success: true, 
          data: serialize_task_with_version(task.reload)
        }
      else
        render json: { error: task.errors.full_messages }, status: :unprocessable_entity
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages }, status: :unprocessable_entity
  rescue StandardError => e
    render json: { error: "Failed to create task: #{e.message}" }, status: :internal_server_error
  end

  def update
    ActiveRecord::Base.transaction do
      current_version = @task.current_version
      
      # Check for merge conflicts before updating
      last_approved = @task.versions.where(status: 'approved').order(version_number: :desc).first
      
      if current_version && last_approved && current_version.base_outdated?(last_approved)
        # Return merge conflict response
        return render json: {
          merge_conflict: true,
          message: "New content has been published. Please review and merge the changes.",
          user_version: serialize_version_with_nodes(current_version),
          current_approved: serialize_version_with_nodes(last_approved),
          diff: current_version.diff_with(last_approved)
        }
      end
      
      # If task is approved and we're making changes, create new version
      if @task.approved? && current_version
        new_version = current_version.create_new_draft(@task.editor)
        @task.update!(current_version: new_version, status: :draft)
        current_version = new_version
      end
      
      # Update task metadata (not content)
      task_updates = task_params_without_action
      if @task.update(task_updates)
        # Update action nodes if provided
        if params[:action_nodes].present?
          # Clear existing nodes safely (children first, then parents)
          root_nodes = current_version.action_nodes.order(:position)
          root_nodes.each(&:safe_destroy)
          create_action_nodes_for_version(current_version, params[:action_nodes])
        elsif params[:task][:action_to_be_taken].present?
          # Fallback: update with HTML content
          root_nodes = current_version.action_nodes.order(:position)
          root_nodes.each(&:safe_destroy)
          current_version.add_action_node(
            content: strip_html_tags(params[:task][:action_to_be_taken]),
            level: 1,
            list_style: 'paragraph',
            node_type: 'paragraph'
          )
        end
        
        # Update task's review_date based on node dates (no sorting)
        current_version.update_and_resort_nodes
        
        render json: { 
          success: true, 
          data: serialize_task_with_version(@task.reload)
        }
      else
        render json: { error: @task.errors.full_messages }, status: :unprocessable_entity
      end
    end
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages }, status: :unprocessable_entity
  end

  def destroy   #change soft delete
    pp"task = #{@task}, @task.editor = #{@task.editor}, current_user = #{current_user}"
    if  @task #current_user == @task.editor && @task.draft?
      @task.destroy
      render json: { success: true }
    else
      render json: { error: 'Unauthorized to delete this task' }, status: :unauthorized
    end
  end

  def send_for_review
    begin
      reviewer_id = params.require(:reviewer_id)
      reviewer = User.find(reviewer_id)
      
      current_version = @task.current_version
      return render json: { error: 'No current version found' }, status: :unprocessable_entity unless current_version
      
      # Update current version status to under_review
      current_version.update!(status: 'under_review')
      
      # Find the last approved version for comparison (base version)
      base_version = @task.versions.where(status: 'approved').order(version_number: :desc).first
      
      # Create a review comparing current version with base version
      review = Review.create!(
        task_version: current_version,
        base_version: base_version, # nil if this is the first review
        reviewer: reviewer,
        status: 'pending'
      )
      
      # Update task status (remove reviewer_id as each version has its own reviewer)
      @task.update!(status: :under_review)
      
      # Determine if this is modified content or new task
      content_type = if base_version && current_version.has_content_changes?
                       'Modified content'
                     else
                       'New task'
                     end
      
      # Create notification with review reference
      Notification.create!(
        recipient: reviewer,
        task: @task,
        review: review,
        message: "New review requested for '#{@task.description}' - #{content_type}",
        notification_type: 'review_request'
      )
      
      render json: { 
        success: true, 
        review_id: review.id,
        message: 'Task sent for review successfully'
      }
      
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.error "Reviewer not found: #{e.message}"
      render json: { error: "Invalid reviewer: #{reviewer_id}" }, status: :not_found

    rescue ActiveRecord::RecordInvalid => e
      Rails.logger.error "Validation failed: #{e.record.errors.full_messages}"
      render json: { error: e.record.errors.full_messages }, status: :unprocessable_entity

    rescue StandardError => e
      Rails.logger.error "Unexpected error: #{e.message}\n#{e.backtrace.join("\n")}"
      render json: { error: "Internal server error" }, status: :internal_server_error
    end
  end
  # def approve
  #   case current_user.role
  #   when 'reviewer'
  #     if @task.under_review?
  #       @task.update(status: :final_review)
  #       notify_final_reviewer
  #       render json: { success: true, message: 'Task sent for final review' }
  #     else
  #       render json: { error: 'Invalid task status' }, status: :unprocessable_entity
  #     end
  #   when 'final_reviewer'
  #     if @task.final_review?
  #       @task.update(status: :approved)
  #       notify_approval
  #       render json: { success: true, message: 'Task approved' }
  #     else
  #       render json: { error: 'Invalid task status' }, status: :unprocessable_entity
  #     end
  #   else
  #     render json: { error: 'Unauthorized' }, status: :unauthorized
  #   end
  # end
  def approve
    review_id = params[:review_id]
    return render json: { error: 'Review ID required' }, status: :unprocessable_entity unless review_id
    
    case current_user.role
    when 'reviewer'
      begin
        review = Review.find(review_id)
        
        # Verify this reviewer owns this review
        unless review.reviewer == current_user
          return render json: { error: 'Unauthorized to approve this review' }, status: :unauthorized
        end
        
        # Verify review is pending
        unless review.status == 'pending'
          return render json: { error: 'Review is not in pending status' }, status: :unprocessable_entity
        end
        
        ActiveRecord::Base.transaction do
          # Approve the review and version
          review.update!(status: 'approved')
          review.task_version.update!(status: 'approved')
          
          # Update task with the approved version as current version
          @task.update!(
            status: :approved,
            current_version: review.task_version
          )
          
          # Update and resort nodes in the approved version
          review.task_version.update_and_resort_nodes
          
          # Notify relevant users
          notify_task_approval(review)
        end
        
        render json: { 
          success: true, 
          message: 'Version approved successfully',
          version_id: review.task_version.id
        }
        
      rescue ActiveRecord::RecordNotFound
        render json: { error: 'Review not found' }, status: :not_found
      rescue ActiveRecord::RecordInvalid => e
        render json: { error: e.record.errors.full_messages }, status: :unprocessable_entity
      end
    else
      render json: { error: 'Unauthorized - Only reviewers can approve' }, status: :unauthorized
    end
  end
  def complete
    if @task.update(completed_at: Time.current, status: :completed)
      notify_completion
      render json: { success: true }
    else
      render json: { error: 'Unable to mark task as complete' }, status: :unprocessable_entity
    end
  end
  def mark_incomplete
    if @task.update(
      status: :draft,
      completed_at: nil
    )
      notify_incomplete
      render json: { success: true }
    else
      render json: { error: 'Unable to mark task as incomplete' }, status: :unprocessable_entity
    end
  end

  # New endpoint for resolving merge conflicts
  def resolve_merge
    current_version = @task.current_version
    last_approved = @task.versions.where(status: 'approved').order(version_number: :desc).first
    
    return render json: { error: 'No merge conflict to resolve' }, status: :unprocessable_entity unless current_version && last_approved
    
    selected_node_ids = params[:selected_node_ids] || []
    
    if current_version.merge_nodes_from(last_approved, selected_node_ids)
      # Update base_version to reflect the merge
      current_version.update!(base_version: last_approved)
      
      render json: {
        success: true,
        message: 'Merge completed successfully',
        data: serialize_version_with_nodes(current_version.reload)
      }
    else
      render json: {
        success: false,
        error: 'Failed to merge changes'
      }, status: :unprocessable_entity
    end
  end

  private

  def serialize_tasks_with_versions(tasks)
    tasks.map { |task| serialize_task_with_version(task) }
  end

  def serialize_task_with_version(task)
    base_task = task.as_json
    
    if task.current_version
      # Add version-specific data
      base_task['current_version_id'] = task.current_version.id
      base_task['version_number'] = task.current_version.version_number
      base_task['action_to_be_taken'] = task.action_to_be_taken
      
      # Get earliest review date from nodes
      if task.current_version.all_action_nodes.any?
        earliest_date = task.current_version.all_action_nodes
                           .where.not(review_date: nil)
                           .minimum(:review_date)
        base_task['review_date'] = earliest_date if earliest_date
      end
    end
    
    base_task
  end

  def serialize_version_with_nodes(version)
    {
      id: version.id,
      version_number: version.version_number,
      status: version.status,
      editor: version.editor.full_name,
      created_at: version.created_at,
      updated_at: version.updated_at,
      nodes: serialize_node_tree(version.node_tree)
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

  def serialize_node(node)
    {
      id: node.id,
      content: node.content,
      level: node.level,
      list_style: node.list_style,
      node_type: node.node_type,
      position: node.position,
      review_date: node.review_date,
      completed: node.completed,
      parent_id: node.parent_id,
      display_counter: node.display_counter
    }
  end

  def create_action_nodes_for_version(version, nodes_data)
    # Handle both flat and hierarchical node structures
    flat_nodes = flatten_node_structure(nodes_data)
    
    # Create nodes in order, handling parent relationships
    node_mapping = {} # Map temp IDs to real IDs
    
    flat_nodes.each do |node_data|
      # Handle parent relationship
      parent_node = nil
      if node_data['parent_id'] && node_data['parent_id'].to_i < 0
        # Temporary parent ID - look up in mapping
        parent_node = node_mapping[node_data['parent_id'].to_i]
      elsif node_data['parent_id'] && node_data['parent_id'].to_i > 0
        # Real parent ID
        parent_node = version.all_action_nodes.find_by(id: node_data['parent_id'])
      end
      
      new_node = version.add_action_node(
        content: node_data['content'],
        level: node_data['level'] || 1,
        list_style: node_data['list_style'] || 'decimal',
        node_type: node_data['node_type'] || 'point',
        parent: parent_node,
        review_date: node_data['review_date']
      )
      
      # Store mapping for temporary IDs
      if node_data['id'] && node_data['id'].to_i < 0
        node_mapping[node_data['id'].to_i] = new_node
      end
    end
  end
  
  def flatten_node_structure(nodes_data)
    # If nodes_data is already flat, return as is
    return nodes_data unless nodes_data.first&.key?('children')
    
    # Otherwise, flatten hierarchical structure
    flat_nodes = []
    nodes_data.each do |node_item|
      if node_item.key?('node')
        # Tree structure: {node: {...}, children: [...]}
        flat_nodes << node_item['node']
        flat_nodes.concat(flatten_node_structure(node_item['children'])) if node_item['children']&.any?
      else
        # Already flat structure
        flat_nodes << node_item
      end
    end
    flat_nodes
  end

  def strip_html_tags(html_content)
    html_content.gsub(/<[^>]*>/, '').strip
  end

  def task_params_without_action
    params.require(:task).permit(
      :sector_division,
      :description,
      :original_date,
      :responsibility,
      :review_date
    )
  end

  def notify_task_approval(review)
    # Notify editor about approval
    Notification.create(
      recipient: review.task_version.editor,
      task: @task,
      review: review,
      message: "Your task '#{@task.description}' has been approved",
      notification_type: :task_approved
    )
  end

  def set_task
    @task = Task.find(params[:id])
  end

  def task_params
    params.require(:task).permit(
      :sector_division,
      :description,
      :action_to_be_taken,
      :original_date,
      :responsibility,
      :review_date,
      :status
    )
  end

  def notify_final_reviewer
    # This method is no longer used since we removed final_reviewer concept
    # Each version has its own reviewer through the Review model
    Rails.logger.warn "notify_final_reviewer called but final_reviewer concept is deprecated"
  end

  def notify_approval
    # Get all reviewers who have been involved with this task
    all_reviewers = @task.versions.joins(:reviews).pluck('reviews.reviewer_id').uniq.map { |id| User.find(id) }
    
    [@task.editor].concat(all_reviewers).uniq.each do |user|
      Notification.create(
        recipient: user,
        task: @task,
        message: "Task '#{@task.description}' has been approved",
        notification_type: :task_approved
      )
    end
  end

  def notify_completion
    # Get all reviewers who have been involved with this task
    all_reviewers = @task.versions.joins(:reviews).pluck('reviews.reviewer_id').uniq.map { |id| User.find(id) }
    
    [@task.editor].concat(all_reviewers).uniq.each do |user|
      Notification.create(
        recipient: user,
        task: @task,
        message: "Task '#{@task.description}' has been marked as completed",
        notification_type: :task_completed
      )
    end
  end

  def notify_incomplete
    # Get all reviewers who have been involved with this task
    all_reviewers = @task.versions.joins(:reviews).pluck('reviews.reviewer_id').uniq.map { |id| User.find(id) }
    
    [@task.editor].concat(all_reviewers).uniq.each do |user|
      Notification.create(
        recipient: user,
        task: @task,
        message: "Task '#{@task.description}' has been marked as incomplete and needs review",
        notification_type: :task_approved
      )
    end
  end
end
