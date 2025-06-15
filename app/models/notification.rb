class Notification < ApplicationRecord
  acts_as_paranoid
  belongs_to :recipient, class_name: 'User'
  belongs_to :task
  belongs_to :comment, optional: true
  belongs_to :review, optional: true
  belongs_to :action_node, optional: true

  validates :message, presence: true

  enum notification_type: {
    review_request: 'review_request',
    review_forwarded: 'review_forwarded',
    comment: 'comment',
    task_approved: 'task_approved',
    changes_requested: 'changes_requested',
    task_completed: 'task_completed',
    comment_resolved: 'comment_resolved',

  }
  validates :notification_type, presence: true

  scope :unread, -> { where(read: false) }
  after_create :broadcast_notification

  private

  def broadcast_notification
    ActionCable.server.broadcast(
      "notifications_#{recipient_id}",
      {
        id: id,
        message: message,
        task_id: task_id,
        notification_type: notification_type,
        created_at: created_at,
        read: read
      }
    )
  end
  def mark_as_read!
    update!(read: true)
  end
end
