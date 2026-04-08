class Notification < ApplicationRecord
  acts_as_paranoid
  belongs_to :recipient, class_name: 'User'
  belongs_to :task, optional: true
  belongs_to :new_task, optional: true
  belongs_to :review, optional: true

  validates :message, presence: true

  enum notification_type: {
    review_request: 'review_request',
    review_forwarded: 'review_forwarded',
    comment: 'comment',
    task_approved: 'task_approved',
    changes_requested: 'changes_requested',
    task_completed: 'task_completed',
    comment_resolved: 'comment_resolved',
    partial_approval: 'partial_approval',
    review_reminder: 'review_reminder',
    editor_changes: 'editor_changes',
    pack_assignment: 'pack_assignment'
  }
  validates :notification_type, presence: true
  scope :unread, -> { where(read: false) }

  def mark_as_read!
    update!(read: true)
  end
end
