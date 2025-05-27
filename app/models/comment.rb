class Comment < ApplicationRecord
  belongs_to :task
  belongs_to :user

  validates :content, presence: true

  after_create :notify_relevant_users

  private

  def notify_relevant_users
    relevant_users = [
      task.editor,
      task.reviewer,
      task.final_reviewer
    ].compact.reject { |u| u == user }

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
