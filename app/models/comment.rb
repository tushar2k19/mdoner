class Comment < ApplicationRecord
  acts_as_paranoid
  # belongs_to :task
  belongs_to :user
  belongs_to :comment_trail
  belongs_to :action_node, optional: true

  validates :content, presence: true
  validates :comment_trail, presence: true
  attribute :resolved, :boolean, default: false
  after_create :notify_relevant_users

  delegate :task, to: :comment_trail

  scope :resolved, -> { where(resolved: true) }
  scope :pending, -> { where(resolved: false) }
  private

  def notify_relevant_users
    # relevant_users = [
    #   task.editor,
    #   task.reviewer,
    #   task.final_reviewer
    # ].compact.reject { |u| u == user }
    relevant_users = [comment_trail.review.task_version.editor] +
                 comment_trail.review.task_version.all_reviewers -
                 [user]
    relevant_users.each do |recipient|
      Notification.create(
        recipient: recipient,
        task: task,
        message: "New comment on task '#{task.description}' by #{user.full_name}",
        notification_type: 'comment',
        comment_id: id
      )
    end
  end
end
