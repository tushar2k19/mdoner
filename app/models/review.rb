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
  validate :consistent_versions


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

  private
  
  def consistent_versions
    # Skip validation if base_version is nil (first review)
    return if base_version.nil?
    
    if task_version.task_id != base_version.task_id
      errors.add(:base_version, "must belong to the same task")
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
