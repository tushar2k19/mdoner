# app/models/review.rb
class Review < ApplicationRecord
  belongs_to :task_version
  belongs_to :base_version, class_name: 'TaskVersion', optional: true
  belongs_to :reviewer, class_name: 'User'
  has_one :comment_trail, dependent: :destroy
  has_many :notifications, dependent: :destroy
  after_create :send_notifications
  after_update :update_task_status
  enum status: {
    pending: 'pending',
    approved: 'approved',
    changes_requested: 'changes_requested',
    forwarded: 'forwarded' # New status for forwarded reviews
  }
  validates :reviewer, presence: true
  validates :reviewer_type, inclusion: { in: %w[task_level node_level] }
  validate :consistent_versions
  validate :assigned_node_ids_format

  # Serialize assigned_node_ids as JSON
  serialize :assigned_node_ids, JSON


  def diff
    {
      added_nodes: added_nodes,
      removed_nodes: removed_nodes,
      modified_nodes: modified_nodes
    }
  end

  def added_nodes
    # If base_version is nil (first review), all nodes are considered "added"
    return task_version.all_action_nodes if base_version.nil?
    
    # Find nodes in task_version that don't exist in base_version
    task_version.all_action_nodes.reject do |current_node|
      base_version.all_action_nodes.any? do |base_node|
        nodes_equivalent?(current_node, base_node)
      end
    end
  end

  def removed_nodes
    # If base_version is nil (first review), no nodes are "removed"
    return ActionNode.none if base_version.nil?
    
    # Find nodes in base_version that don't exist in task_version
    base_version.all_action_nodes.reject do |base_node|
      task_version.all_action_nodes.any? do |current_node|
        nodes_equivalent?(current_node, base_node)
      end
    end
  end

  def modified_nodes
    # If base_version is nil (first review), no nodes are "modified"
    return ActionNode.none if base_version.nil?
    
    # Find nodes that exist in both versions but have different content
    modified = []
    task_version.all_action_nodes.each do |current_node|
      base_node = base_version.all_action_nodes.find do |bn|
        nodes_structurally_equivalent?(current_node, bn)
      end
      
      if base_node && !nodes_content_equal?(current_node, base_node)
        modified << current_node
      end
    end
    
    modified
  end

  def forward_to(new_reviewer)
    transaction do
      update!(status: :forwarded)
      Review.create!(
        task_version: task_version,
        base_version: base_version,
        reviewer: new_reviewer,
        status: :pending
      )
    end
  end
  def involved_users
    [reviewer, task_version.editor] +
      Review.where(task_version: task_version).pluck(:reviewer_id).uniq
            .map { |id| User.find(id) }
  end

  # New methods for multi-reviewer support
  
  # Get the nodes assigned to this review
  def assigned_nodes
    return ActionNode.none unless assigned_node_ids.present?
    
    node_ids = assigned_node_ids.is_a?(String) ? JSON.parse(assigned_node_ids) : assigned_node_ids
    task_version.all_action_nodes.where(id: node_ids)
  end

  # Get nodes that have changed for this reviewer
  def changed_nodes
    return ActionNode.none unless assigned_node_ids.present?
    
    current_nodes = assigned_nodes
    return current_nodes if base_version.nil? # First review - all nodes are "changed"
    
    # Find which assigned nodes actually changed
    current_nodes.select do |current_node|
      base_node = base_version.all_action_nodes.find do |bn|
        nodes_equivalent?(current_node, bn)
      end
      
      base_node.nil? || !nodes_content_equal?(current_node, base_node)
    end
  end

  # Check if this review has relevant changes for the reviewer
  def has_relevant_changes_for_reviewer?
    changed_nodes.any?
  end

  # Check if this is a task-level review
  def task_level_review?
    reviewer_type == 'task_level'
  end

  # Check if this is a node-level review
  def node_level_review?
    reviewer_type == 'node_level'
  end

  # Get reviewer status breakdown for dashboard
  def self.get_reviewer_status_breakdown(task_version)
    reviews = where(task_version: task_version)
    breakdown = {
      total_reviews: reviews.count,
      approved_reviews: reviews.where(status: 'approved').count,
      pending_reviews: reviews.where(status: 'pending').count,
      changes_requested: reviews.where(status: 'changes_requested').count,
      reviewers: reviews.includes(:reviewer).map do |review|
        {
          id: review.reviewer.id,
          name: review.reviewer.full_name,
          status: review.status,
          reviewer_type: review.reviewer_type,
          assigned_node_count: review.assigned_node_ids&.length || 0
        }
      end
    }
    
    breakdown[:all_approved] = breakdown[:total_reviews] > 0 && breakdown[:approved_reviews] == breakdown[:total_reviews]
    breakdown
  end

  private
  
  def consistent_versions
    # Skip validation if base_version is nil (first review)
    return if base_version.nil?
    
    if task_version.task_id != base_version.task_id
      errors.add(:base_version, "must belong to the same task")
    end
  end

  def assigned_node_ids_format
    return unless assigned_node_ids.present?
    
    begin
      node_ids = assigned_node_ids.is_a?(String) ? JSON.parse(assigned_node_ids) : assigned_node_ids
      unless node_ids.is_a?(Array)
        errors.add(:assigned_node_ids, "must be an array of node IDs")
        return
      end
      
      # Skip validation during status changes to avoid timing issues
      # The assigned_node_ids are validated when the review is created, not when status changes
      if status_changed? && (status == 'approved' || status == 'changes_requested')
        Rails.logger.info "🔧 SKIPPING node validation for review #{id} - status changed to #{status}"
        return
      end
      
      # Skip validation if task version is being updated (to avoid race conditions)
      if task_version.status_changed? && task_version.status == 'approved'
        Rails.logger.info "🔧 SKIPPING node validation for review #{id} - task version status changed to approved"
        return
      end
      
      # Validate that all node IDs exist in the task version
      existing_node_ids = task_version.all_action_nodes.pluck(:id)
      invalid_ids = node_ids - existing_node_ids
      
      if invalid_ids.any?
        Rails.logger.error "🔧 VALIDATION ERROR for review #{id}:"
        Rails.logger.error "🔧 Expected node IDs: #{node_ids.inspect}"
        Rails.logger.error "🔧 Existing node IDs: #{existing_node_ids.inspect}"
        Rails.logger.error "🔧 Invalid node IDs: #{invalid_ids.inspect}"
        Rails.logger.error "🔧 Task version status: #{task_version.status}"
        Rails.logger.error "🔧 Review status: #{status}"
        
        errors.add(:assigned_node_ids, "contains invalid node IDs: #{invalid_ids.join(', ')}")
      end
    rescue JSON::ParserError
      errors.add(:assigned_node_ids, "must be valid JSON")
    end
  end
  
  def send_notifications
    # Notify reviewer
    Notification.create!(
      recipient: reviewer,
      task: task_version.task,
      review: self,
      message: "New review requested for #{task_version.task.description}",
      notification_type: 'review_request'
    )

    # Notify editor if forwarded
    if status == 'forwarded'
      Notification.create!(
        recipient: task_version.editor,
        task: task_version.task,
        review: self,
        message: "Your task has been forwarded to another reviewer",
        notification_type: 'review_forwarded'
      )
    end
  end
  def update_task_status
    case status
    when 'approved'
      task_version.update!(status: :approved)
      task_version.task.update!(current_version: task_version)
    when 'changes_requested'
      task_version.update!(status: :draft)
    end
  end

  def nodes_equivalent?(node1, node2)
    # Compare content and structure, but not position (which can change)
    node1.content.strip == node2.content.strip &&
    node1.level == node2.level &&
    node1.list_style == node2.list_style
  end

  def nodes_structurally_equivalent?(node1, node2)
    # Check if nodes represent the same logical content
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
