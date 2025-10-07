class TaskController < ApplicationController
  # before_action :authorize_access_request!
  before_action :set_task, only: [
    :update,
    :destroy,
    :send_for_review,
    :approve,
    :resolve_merge,
    :merge_analysis,
    :apply_merge,
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
                      end
    completed_tasks = completed_tasks.order(completed_at: :desc)

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
        
        # Apply tags if provided
        if params[:task][:tag_ids].is_a?(Array)
          apply_tags!(task, params[:task][:tag_ids])
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
      
      # If task is approved and we're making changes, create new version
      if @task.approved? && current_version
        new_version = current_version.create_new_draft(@task.editor)
        @task.update!(current_version: new_version, status: :draft)
        current_version = new_version
      end
      
      # Update task metadata (not content)
      task_updates = task_params_without_action
      if @task.update(task_updates)
        # Check if content is being modified - if so, change status back to draft
        content_being_modified = params[:action_nodes].present? || params[:task][:action_to_be_taken].present?
        
        if content_being_modified && (@task.under_review? || @task.approved?)
          # Change status back to draft when editor modifies content during review or after approval
          @task.update!(status: :draft)
          current_version.update!(status: :draft) if current_version
        end
        
        # SAVE NEW CONTENT FIRST before checking merge conflicts
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
        
        # Replace tags if provided
        if params[:task][:tag_ids].is_a?(Array)
          apply_tags!(@task, params[:task][:tag_ids])
        end

        # NOW check for merge conflicts AFTER saving the new content
        last_approved = @task.versions.where(status: 'approved').order(version_number: :desc).first
        
        if current_version && last_approved && current_version.base_outdated?(last_approved)
          # Enhanced merge conflict response with three-way diff analysis
          # Now current_version contains Editor 2's latest content
          return render json: {
            merge_conflict: true,
            message: "New content has been published. Please review and merge the changes.",
            current_user_version: serialize_version_with_nodes(current_version.reload),
            latest_approved_version: serialize_version_with_nodes(last_approved),
            base_version: serialize_version_with_nodes(current_version.base_version),
            diff_analysis: generate_three_way_diff_analysis(current_version, last_approved),
            merge_suggestions: generate_merge_suggestions(current_version, last_approved),
            auto_mergeable_count: count_auto_mergeable_changes(current_version, last_approved),
            conflict_count: count_conflicts(current_version, last_approved)
          }
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
      
      # Use new smart review creation logic
      created_reviews = create_smart_reviews(current_version, base_version, reviewer_id)
      
      if created_reviews.any?
        # Send smart notifications only to reviewers with relevant changes
        send_smart_notifications(created_reviews)
        
        message = "Task sent for review to #{created_reviews.count} reviewer(s)"
      else
        message = 'No reviewers needed - no relevant changes detected'
      end
      
      # Update task status
      @task.update!(status: :under_review)
      
      render json: { 
        success: true, 
        review_ids: created_reviews.map(&:id),
        message: message
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

  # Get comprehensive merge analysis for frontend merge interface
  def merge_analysis
    current_version = @task.current_version
    last_approved = @task.versions.where(status: 'approved').order(version_number: :desc).first
    base_version = current_version&.base_version
    
    return render json: { error: 'No merge conflict exists' }, status: :unprocessable_entity unless current_version && last_approved && current_version.base_outdated?(last_approved)
    
    # Generate enhanced merge categorization
    merge_categorization = generate_enhanced_merge_categorization(current_version, last_approved, base_version)
    
    render json: {
      success: true,
      data: {
        current_user_version: serialize_version_with_nodes(current_version),
        latest_approved_version: serialize_version_with_nodes(last_approved),
        base_version: serialize_version_with_nodes(base_version),
        diff_analysis: generate_three_way_diff_analysis(current_version, last_approved),
        merge_suggestions: generate_merge_suggestions(current_version, last_approved),
        
        # Enhanced categorization for proper UI display
        node_categorization: merge_categorization,
        
        # Legacy fields for backward compatibility
        auto_mergeable_changes: merge_categorization[:auto_approved] + merge_categorization[:user_only],
        conflicts: merge_categorization[:conflicts],
        
        statistics: {
          original_nodes: merge_categorization[:original].length,
          approved_auto_accept: merge_categorization[:auto_approved].length,
          user_pending: merge_categorization[:user_only].length,
          conflicts: merge_categorization[:conflicts].length,
          total_decisions_needed: merge_categorization[:user_only].length + merge_categorization[:conflicts].length
        }
      }
    }
  rescue StandardError => e
    Rails.logger.error "Merge analysis error: #{e.message}\n#{e.backtrace.join("\n")}"
    render json: { error: "Failed to analyze merge conflicts" }, status: :internal_server_error
  end

  # Apply merged content to update V2 in-place
  def apply_merge
    current_version = @task.current_version
    last_approved = @task.versions.where(status: 'approved').order(version_number: :desc).first
    merged_nodes = params[:merged_action_nodes]
    merge_choices = params[:merge_choices] || {}
    
    return render json: { error: 'No current version found' }, status: :unprocessable_entity unless current_version
    return render json: { error: 'No merged content provided' }, status: :unprocessable_entity unless merged_nodes.present?
    
    ActiveRecord::Base.transaction do
      # Clear existing nodes in V2 (current_version)
      current_version.all_action_nodes.destroy_all
      
      # Create new nodes with merged content
      create_action_nodes_for_version(current_version, merged_nodes)
      
      # Update base_version to point to V3 for proper review comparison
      current_version.update!(base_version: last_approved) if last_approved
      
      # Log merge decision for audit trail
      Rails.logger.info "Merge applied to version #{current_version.id} by user #{current_user.id}. Choices: #{merge_choices}"
      
      render json: {
        success: true,
        message: 'Merge applied successfully. Version updated in-place.',
        data: {
          updated_version: serialize_version_with_nodes(current_version.reload),
          merge_summary: generate_merge_summary(merge_choices),
          next_steps: {
            action: 'send_for_review',
            message: 'Your merged content is ready for review'
          }
        }
      }
    end
  rescue ActiveRecord::RecordInvalid => e
    Rails.logger.error "Merge application failed: #{e.record.errors.full_messages}"
    render json: { 
      success: false, 
      error: e.record.errors.full_messages 
    }, status: :unprocessable_entity
  rescue StandardError => e
    Rails.logger.error "Merge application error: #{e.message}\n#{e.backtrace.join("\n")}"
    render json: { 
      success: false, 
      error: "Failed to apply merge" 
    }, status: :internal_server_error
  end

  private

  def serialize_tasks_with_versions(tasks)
    tasks.map { |task| serialize_task_with_version(task) }
  end

  def serialize_task_with_version(task)
    base_task = task.as_json
    current_version = task.current_version

    # Add version-specific data
    base_task.merge!(
      'action_to_be_taken' => task.action_to_be_taken,
      'current_version' => current_version ? {
        'id' => current_version.id,
        'version_number' => current_version.version_number,
        'status' => current_version.status,
        'editor_name' => current_version.editor.full_name,
        'editor_id' => current_version.editor.id,
        'action_nodes' => serialize_flat_node_hierarchy(current_version.node_tree)
      } : nil,
      'editor_name' => task.editor.full_name,
      'editor_id' => task.editor.id,
      'reviewer_info' => task.reviewer_info,
      'tags' => task.tags.select(:id, :name)
    )

    # Add completion info if task is completed
    if task.completed?
      base_task['completed_at'] = task.completed_at
    end

    base_task
  end

  def apply_tags!(task, tag_ids)
    tag_ids = tag_ids.map(&:to_i).uniq
    existing_ids = task.tags.pluck(:id)

    to_add = tag_ids - existing_ids
    to_remove = existing_ids - tag_ids

    TaskTag.where(task_id: task.id, tag_id: to_remove).delete_all if to_remove.any?

    to_add.each do |tid|
      TaskTag.create!(task_id: task.id, tag_id: tid, created_by_id: current_user.id)
    end
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

  def serialize_flat_node_hierarchy(tree_nodes)
    # Convert tree structure to flat hierarchy for frontend subtask calculations
    tree_nodes.map do |tree_item|
      node = serialize_node(tree_item[:node])
      # Always include children array (empty if no children) for frontend compatibility
      node['children'] = tree_item[:children].any? ? serialize_flat_node_hierarchy(tree_item[:children]) : []
      node
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
      display_counter: node.display_counter,
      reviewer_id: node.reviewer_id,
      reviewer_name: node.reviewer&.first_name  # Include reviewer name if reviewer exists
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
        review_date: node_data['review_date'],
        completed: node_data['completed'] || false,
        reviewer_id: node_data['reviewer_id'] # Add reviewer_id when recreating nodes
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
      :review_date,
      tag_ids: []
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
      :status,
      tag_ids: []
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

  # ========================================
  # ENHANCED MERGE CONFLICT SYSTEM METHODS
  # ========================================

  # Generate enhanced merge categorization for proper UI display
  def generate_enhanced_merge_categorization(user_version, approved_version, base_version)
    return { error: 'Missing base version' } unless base_version
    
    # Get all nodes from all versions
    base_nodes = base_version.all_action_nodes.to_a
    user_nodes = user_version.all_action_nodes.to_a
    approved_nodes = approved_version.all_action_nodes.to_a
    
    categorization = {
      original: [],           # Nodes unchanged from base (auto-accept, no color)
      auto_approved: [],      # Approved changes only (blue, auto-accept)
      user_only: [],          # User changes only (green, pending approval)
      conflicts: []           # Both modified same node (red, manual resolution)
    }
    
    # Process each base node to determine its fate
    base_nodes.each do |base_node|
      user_node = find_equivalent_node_in_version(base_node, user_version)
      approved_node = find_equivalent_node_in_version(base_node, approved_version)
      
      user_modified = user_node && !nodes_content_identical?(base_node, user_node)
      approved_modified = approved_node && !nodes_content_identical?(base_node, approved_node)
      
      if !user_modified && !approved_modified
        # Node unchanged by both editors - keep original
        categorization[:original] << {
          node: serialize_node_for_conflict(base_node),
          status: 'original',
          action: 'auto_accept'
        }
      elsif !user_modified && approved_modified
        # Only approved editor modified - auto-accept approved version
        categorization[:auto_approved] << {
          node: serialize_node_for_conflict(approved_node),
          status: 'approved_only',
          action: 'auto_accept',
          source: 'approved_editor'
        }
      elsif user_modified && !approved_modified
        # Only user modified - needs approval
        categorization[:user_only] << {
          node: serialize_node_for_conflict(user_node),
          status: 'user_only',
          action: 'needs_approval',
          source: 'current_user'
        }
      elsif user_modified && approved_modified
        # Both modified - conflict resolution needed
        if nodes_content_identical?(user_node, approved_node)
          # Same changes made by both - auto-accept
          categorization[:auto_approved] << {
            node: serialize_node_for_conflict(user_node),
            status: 'both_same',
            action: 'auto_accept',
            source: 'both_editors'
          }
        else
          # Different changes - manual resolution required
          categorization[:conflicts] << {
            base_node: serialize_node_for_conflict(base_node),
            user_version: serialize_node_for_conflict(user_node),
            approved_version: serialize_node_for_conflict(approved_node),
            status: 'conflict',
            action: 'manual_resolve',
            conflict_type: determine_conflict_type(base_node, user_node, approved_node),
            resolution_suggestions: generate_conflict_resolution_suggestions(base_node, user_node, approved_node)
          }
        end
      end
    end
    
    # Handle new nodes added by user (not in base)
    user_nodes.each do |user_node|
      unless find_equivalent_node_in_version(user_node, base_version)
        # New node added by user - needs approval
        categorization[:user_only] << {
          node: serialize_node_for_conflict(user_node),
          status: 'user_added',
          action: 'needs_approval',
          source: 'current_user'
        }
      end
    end
    
    # Handle new nodes added by approved editor (not in base)
    approved_nodes.each do |approved_node|
      unless find_equivalent_node_in_version(approved_node, base_version)
        # Check if user also added this node
        user_equivalent = find_equivalent_node_in_version(approved_node, user_version)
        if user_equivalent
          # Both added similar node - conflict or auto-merge
          if nodes_content_identical?(approved_node, user_equivalent)
            # Same addition - auto-accept
            categorization[:auto_approved] << {
              node: serialize_node_for_conflict(approved_node),
              status: 'both_added_same',
              action: 'auto_accept',
              source: 'both_editors'
            }
          else
            # Different additions - conflict
            categorization[:conflicts] << {
              base_node: nil,
              user_version: serialize_node_for_conflict(user_equivalent),
              approved_version: serialize_node_for_conflict(approved_node),
              status: 'addition_conflict',
              action: 'manual_resolve',
              conflict_type: 'both_added_different',
              resolution_suggestions: generate_conflict_resolution_suggestions(nil, user_equivalent, approved_node)
            }
          end
        else
          # Only approved editor added - auto-accept
          categorization[:auto_approved] << {
            node: serialize_node_for_conflict(approved_node),
            status: 'approved_added',
            action: 'auto_accept',
            source: 'approved_editor'
          }
        end
      end
    end
    
    categorization
  end

  # Generate comprehensive three-way diff analysis (V1 ↔ V2 ↔ V3)
  def generate_three_way_diff_analysis(user_version, approved_version)
    base_version = user_version.base_version
    return { error: 'No base version found' } unless base_version

    {
      # Changes made by current user: V2 vs V1
      user_changes: {
        added: find_added_nodes(user_version, base_version),
        modified: find_modified_nodes(user_version, base_version),
        deleted: find_deleted_nodes(user_version, base_version)
      },
      
      # Changes made by other editor: V3 vs V1
      approved_changes: {
        added: find_added_nodes(approved_version, base_version),
        modified: find_modified_nodes(approved_version, base_version),
        deleted: find_deleted_nodes(approved_version, base_version)
      },
      
      # Direct conflicts: Same base node modified differently
      conflicts: detect_content_conflicts(user_version, approved_version, base_version),
      
      # Analysis metadata
      analysis_timestamp: Time.current,
      base_version_info: {
        id: base_version.id,
        version_number: base_version.version_number
      }
    }
  end

  # Generate intelligent merge suggestions
  def generate_merge_suggestions(user_version, approved_version)
    suggestions = []
    base_version = user_version.base_version
    return suggestions unless base_version

    # Suggestion 1: Auto-merge non-conflicting changes
    auto_mergeable = identify_auto_mergeable_changes(user_version, approved_version)
    if auto_mergeable.any?
      suggestions << {
        type: 'auto_merge',
        title: 'Auto-merge Safe Changes',
        description: "#{auto_mergeable.length} changes can be merged automatically",
        action: 'apply_auto_merge',
        confidence: 'high'
      }
    end

    # Suggestion 2: Position-only conflicts (same content, different positions)
    position_conflicts = find_position_only_conflicts(user_version, approved_version)
    if position_conflicts.any?
      suggestions << {
        type: 'position_resolution',
        title: 'Resolve Position Conflicts',
        description: "#{position_conflicts.length} nodes have position conflicts only",
        action: 'resolve_positions',
        confidence: 'medium'
      }
    end

    # Suggestion 3: Content conflicts requiring manual review
    content_conflicts = detect_content_conflicts(user_version, approved_version, base_version)
    if content_conflicts.any?
      suggestions << {
        type: 'manual_review',
        title: 'Manual Review Required',
        description: "#{content_conflicts.length} content conflicts need your decision",
        action: 'manual_resolve',
        confidence: 'requires_attention'
      }
    end

    suggestions
  end

  # Count auto-mergeable changes
  def count_auto_mergeable_changes(user_version, approved_version)
    identify_auto_mergeable_changes(user_version, approved_version).length
  end

  # Count conflicts requiring manual resolution
  def count_conflicts(user_version, approved_version)
    base_version = user_version.base_version
    return 0 unless base_version
    detect_content_conflicts(user_version, approved_version, base_version).length
  end

  # Count total changes across both versions
  def count_total_changes(user_version, approved_version)
    base_version = user_version.base_version
    return 0 unless base_version

    user_changes = user_version.diff_with(base_version)
    approved_changes = approved_version.diff_with(base_version)
    
    (user_changes[:added_nodes].length + user_changes[:modified_nodes].length + 
     approved_changes[:added_nodes].length + approved_changes[:modified_nodes].length)
  end

  # Identify changes that can be auto-merged safely
  def identify_auto_mergeable_changes(user_version, approved_version)
    base_version = user_version.base_version
    return [] unless base_version

    auto_mergeable = []
    
    # Different nodes modified by each editor (no overlap)
    user_modified_ids = find_modified_nodes(user_version, base_version).map(&:id)
    approved_modified_ids = find_modified_nodes(approved_version, base_version).map(&:id)
    
    # Non-overlapping modifications can be auto-merged
    user_only_changes = user_modified_ids - approved_modified_ids
    approved_only_changes = approved_modified_ids - user_modified_ids
    
    auto_mergeable.concat(user_version.all_action_nodes.where(id: user_only_changes))
    auto_mergeable.concat(approved_version.all_action_nodes.where(id: approved_only_changes))
    
    auto_mergeable
  end

  # Identify conflicts requiring manual resolution
  def identify_conflicts(user_version, approved_version)
    base_version = user_version.base_version
    return [] unless base_version
    
    detect_content_conflicts(user_version, approved_version, base_version)
  end

  # Generate summary of merge decisions
  def generate_merge_summary(merge_choices)
    return { message: 'No merge choices provided' } if merge_choices.blank?

    {
      total_decisions: merge_choices.length,
      user_content_chosen: merge_choices.values.count('user'),
      approved_content_chosen: merge_choices.values.count('approved'),
      custom_merges: merge_choices.values.count('custom'),
      merge_strategy: determine_merge_strategy(merge_choices)
    }
  end

  # Detect content conflicts (same base node modified differently)
  def detect_content_conflicts(user_version, approved_version, base_version)
    conflicts = []
    
    base_version.all_action_nodes.each do |base_node|
      user_node = find_equivalent_node_in_version(base_node, user_version)
      approved_node = find_equivalent_node_in_version(base_node, approved_version)
      
      # If both editors modified the same base node differently
      if user_node && approved_node && 
         !nodes_content_identical?(user_node, approved_node) &&
         (!nodes_content_identical?(user_node, base_node) || 
          !nodes_content_identical?(approved_node, base_node))
        
        conflicts << {
          base_node: serialize_node_for_conflict(base_node),
          user_version: serialize_node_for_conflict(user_node),
          approved_version: serialize_node_for_conflict(approved_node),
          conflict_type: determine_conflict_type(base_node, user_node, approved_node),
          resolution_suggestions: generate_conflict_resolution_suggestions(base_node, user_node, approved_node)
        }
      end
    end
    
    conflicts
  end

  # Find equivalent node in another version by content matching
  def find_equivalent_node_in_version(base_node, target_version)
    target_version.all_action_nodes.find do |node|
      # Match by content similarity and structural position
      content_similarity_score(base_node.content, node.content) > 0.8 &&
      base_node.level == node.level &&
      base_node.list_style == node.list_style
    end
  end

  # Calculate content similarity score (0.0 to 1.0)
  def content_similarity_score(content1, content2)
    # Simple similarity based on common words
    words1 = content1.downcase.split(/\W+/).reject(&:empty?)
    words2 = content2.downcase.split(/\W+/).reject(&:empty?)
    
    return 1.0 if words1 == words2
    return 0.0 if words1.empty? || words2.empty?
    
    common_words = words1 & words2
    total_words = (words1 + words2).uniq.length
    
    common_words.length.to_f / total_words
  end

  # Check if two nodes have identical content
  def nodes_content_identical?(node1, node2)
    node1.content.strip == node2.content.strip &&
    node1.review_date == node2.review_date &&
    node1.completed == node2.completed
  end

  # Determine type of conflict
  def determine_conflict_type(base_node, user_node, approved_node)
    if base_node.content != user_node.content && base_node.content != approved_node.content
      'content_modified_both'
    elsif base_node.review_date != user_node.review_date && base_node.review_date != approved_node.review_date
      'review_date_modified_both'
    elsif user_node.position != approved_node.position
      'position_conflict'
    else
      'other_conflict'
    end
  end

  # Generate conflict resolution suggestions
  def generate_conflict_resolution_suggestions(base_node, user_node, approved_node)
    suggestions = []
    
    # Content length comparison
    if user_node.content.length > approved_node.content.length
      suggestions << { type: 'longer_content', preference: 'user', reason: 'More detailed content' }
    elsif approved_node.content.length > user_node.content.length
      suggestions << { type: 'longer_content', preference: 'approved', reason: 'More detailed content' }
    end
    
    # Review date comparison
    if user_node.review_date && approved_node.review_date
      if user_node.review_date < approved_node.review_date
        suggestions << { type: 'earlier_date', preference: 'user', reason: 'Earlier review date' }
      elsif approved_node.review_date < user_node.review_date
        suggestions << { type: 'earlier_date', preference: 'approved', reason: 'Earlier review date' }
      end
    end
    
    suggestions
  end

  # Serialize node for conflict display
  def serialize_node_for_conflict(node)
    {
      id: node.id,
      content: node.content,
      level: node.level,
      list_style: node.list_style,
      position: node.position,
      review_date: node.review_date,
      completed: node.completed,
      display_counter: node.display_counter,
      content_preview: node.content.length > 100 ? "#{node.content[0..97]}..." : node.content
    }
  end

  # Find added nodes (present in version but not in base)
  def find_added_nodes(version, base_version)
    version.all_action_nodes.reject do |node|
      find_equivalent_node_in_version(node, base_version)
    end
  end

  # Find modified nodes (content changed from base)
  def find_modified_nodes(version, base_version)
    modified = []
    version.all_action_nodes.each do |node|
      base_node = find_equivalent_node_in_version(node, base_version)
      if base_node && !nodes_content_identical?(node, base_node)
        modified << node
      end
    end
    modified
  end

  # Find deleted nodes (present in base but not in version)
  def find_deleted_nodes(version, base_version)
    base_version.all_action_nodes.reject do |base_node|
      find_equivalent_node_in_version(base_node, version)
    end
  end

  # Find position-only conflicts
  def find_position_only_conflicts(user_version, approved_version)
    conflicts = []
    user_version.all_action_nodes.each do |user_node|
      approved_node = approved_version.all_action_nodes.find do |n|
        n.content.strip == user_node.content.strip && n.level == user_node.level
      end
      
      if approved_node && user_node.position != approved_node.position
        conflicts << { user_node: user_node, approved_node: approved_node }
      end
    end
    conflicts
  end

  # Determine overall merge strategy
  def determine_merge_strategy(merge_choices)
    user_choices = merge_choices.values.count('user')
    approved_choices = merge_choices.values.count('approved')
    
    if user_choices > approved_choices * 2
      'user_preferred'
    elsif approved_choices > user_choices * 2
      'approved_preferred'
    else
      'balanced_merge'
    end
  end

  # New methods for smart multi-reviewer system
  
  def create_smart_reviews(current_version, base_version, task_level_reviewer_id)
    created_reviews = []
    
    # Group nodes by assigned reviewer
    nodes_by_reviewer = current_version.action_nodes.group_by(&:reviewer_id)
    
    Rails.logger.info "🔧 SMART REVIEW CREATION DEBUG:"
    Rails.logger.info "🔧 Total nodes: #{current_version.action_nodes.count}"
    Rails.logger.info "🔧 Nodes by reviewer: #{nodes_by_reviewer.transform_values(&:count)}"
    Rails.logger.info "🔧 Task level reviewer ID: #{task_level_reviewer_id}"
    
    # Create task-level review for unassigned nodes + general oversight
    unassigned_nodes = current_version.action_nodes.where(reviewer_id: nil)
    Rails.logger.info "🔧 Unassigned nodes count: #{unassigned_nodes.count}"
    
    if unassigned_nodes.any? || task_level_reviewer_id.present?
      task_level_review = create_task_level_review(
        task_version: current_version,
        base_version: base_version,
        reviewer_id: task_level_reviewer_id,
        unassigned_nodes: unassigned_nodes
      )
      created_reviews << task_level_review if task_level_review
      Rails.logger.info "✅ Created task-level review: #{task_level_review&.id}"
    end
    
    # Create node-level reviews for explicitly assigned nodes
    nodes_by_reviewer.each do |reviewer_id, assigned_nodes|
      next if reviewer_id.nil? # Skip unassigned nodes (handled above)
      
      Rails.logger.info "🔧 Processing reviewer #{reviewer_id} with #{assigned_nodes.count} nodes"
      
      # Check if any of the reviewer's assigned nodes have changed
      changed_nodes = find_changed_nodes_for_reviewer(assigned_nodes, base_version)
      
      Rails.logger.info "🔧 Changed nodes for reviewer #{reviewer_id}: #{changed_nodes.count}"
      
      if changed_nodes.any?
        node_level_review = create_node_level_review(
          task_version: current_version,
          base_version: base_version,
          reviewer_id: reviewer_id,
          assigned_nodes: changed_nodes
        )
        created_reviews << node_level_review if node_level_review
        Rails.logger.info "✅ Created node-level review: #{node_level_review&.id} for reviewer #{reviewer_id}"
      end
    end
    
    Rails.logger.info "🔧 Total reviews created: #{created_reviews.count}"
    created_reviews
  end

  def create_task_level_review(task_version:, base_version:, reviewer_id:, unassigned_nodes:)
    # Check if there's already a pending task-level review for this version
    existing_review = Review.find_by(
      task_version: task_version, 
      status: 'pending',
      reviewer_type: 'task_level'
    )
    
    if existing_review
      # Update existing task-level review
      existing_review.update!(
        reviewer_id: reviewer_id,
        base_version: base_version,
        assigned_node_ids: unassigned_nodes.pluck(:id).to_json
      )
      existing_review
    else
      # Create new task-level review
      Review.create!(
        task_version: task_version,
        base_version: base_version,
        reviewer_id: reviewer_id,
        status: 'pending',
        reviewer_type: 'task_level',
        is_aggregate_review: true,
        assigned_node_ids: unassigned_nodes.pluck(:id).to_json
      )
    end
  end

  def create_node_level_review(task_version:, base_version:, reviewer_id:, assigned_nodes:)
    # Check if there's already a pending node-level review for this reviewer
    existing_review = Review.find_by(
      task_version: task_version,
      reviewer_id: reviewer_id,
      status: 'pending',
      reviewer_type: 'node_level'
    )
    
    if existing_review
      # Update existing node-level review
      existing_review.update!(
        base_version: base_version,
        assigned_node_ids: assigned_nodes.pluck(:id).to_json
      )
      existing_review
    else
      # Create new node-level review
      Review.create!(
        task_version: task_version,
        base_version: base_version,
        reviewer_id: reviewer_id,
        status: 'pending',
        reviewer_type: 'node_level',
        is_aggregate_review: false,
        assigned_node_ids: assigned_nodes.pluck(:id).to_json
      )
    end
  end

  def find_changed_nodes_for_reviewer(assigned_nodes, base_version)
    return assigned_nodes if base_version.nil? # First review - all nodes are "changed"
    
    assigned_nodes.select do |current_node|
      # Check if this specific node has changed
      base_node = base_version.action_nodes.find do |bn|
        nodes_equivalent?(current_node, bn)
      end
      
      # Node changed if it doesn't exist in base or content is different
      base_node.nil? || !nodes_content_equal?(current_node, base_node)
    end
  end

  def send_smart_notifications(created_reviews)
    created_reviews.each do |review|
      changed_nodes = review.changed_nodes
      next unless changed_nodes.any? # Only notify if there are actual changes
      
      # Create targeted notification
      Notification.create!(
        recipient: review.reviewer,
        task: @task,
        review: review,
        message: generate_smart_notification_message(changed_nodes, review),
        notification_type: 'review_request'
      )
    end
  end

  def generate_smart_notification_message(changed_nodes, review)
    node_count = changed_nodes.count
    
    if review.task_level_review?
      if node_count == 1
        "1 unassigned node has been modified in task: #{@task.description}"
      else
        "#{node_count} unassigned nodes have been modified in task: #{@task.description}"
      end
    else
      if node_count == 1
        "1 node you're assigned to has been modified in task: #{@task.description}"
      else
        "#{node_count} nodes you're assigned to have been modified in task: #{@task.description}"
      end
    end
  end

  def nodes_equivalent?(node1, node2)
    # Compare content and structure, but not position (which can change)
    node1.content.strip == node2.content.strip &&
    node1.level == node2.level &&
    node1.list_style == node2.list_style
  end

  def nodes_content_equal?(node1, node2)
    node1.content.strip == node2.content.strip &&
    node1.review_date == node2.review_date &&
    node1.completed == node2.completed
  end
end
