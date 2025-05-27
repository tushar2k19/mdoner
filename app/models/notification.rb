class Notification < ApplicationRecord
  belongs_to :recipient, class_name: 'User'
  belongs_to :task
  belongs_to :comment, optional: true

  validates :message, presence: true

  # enum notification_type: {
  #   review_request: 0,
  #   comment: 1,
  #   task_approved: 2,
  #   changes_requested: 3,
  #   task_completed: 4
  # }
  enum notification_type: {
    review_request: 'review_request',
    comment: 'comment',
    task_approved: 'task_approved',
    changes_requested: 'changes_requested',
    task_completed: 'task_completed'
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
end
