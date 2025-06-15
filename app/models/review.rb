# app/models/review.rb
class Review < ApplicationRecord
  belongs_to :task_version
  belongs_to :base_version, class_name: 'TaskVersion'
  belongs_to :reviewer, class_name: 'User'
  has_many :comment_trails, dependent: :destroy
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
  def consistent_versions
    if task_version.task_id != base_version.task_id
      errors.add(:base_version, "must belong to the same task")
    end
  end
  def added_nodes
    task_version.action_nodes.where.not(id: base_version.action_nodes.pluck(:id))
  end

  def removed_nodes
    base_version.action_nodes.where.not(id: task_version.action_nodes.pluck(:id))
  end

  def modified_nodes
    task_version.action_nodes.joins(:base_version_copy)
                .where.not(action_nodes: { content: base_version_copy[:content] })
                .or(where.not(action_nodes: { review_date: base_version_copy[:review_date] }))
                .or(where.not(action_nodes: { completed: base_version_copy[:completed] }))
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
end
