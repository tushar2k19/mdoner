class User < ApplicationRecord
  has_secure_password
  enum role: { editor: 0, reviewer: 1, final_reviewer: 2 }

  has_many :created_tasks, class_name: 'Task', foreign_key: 'editor_id'
  has_many :review_tasks, class_name: 'Task', foreign_key: 'reviewer_id'
  # A user can be the editor of many tasks, so you can get all the tasks a user created using user.created_tasks
  # a task has 1 editor, 1 reviewer right. so a user could be editor to multiple tasks and reviewer to many tasks as well.
  # so user.created_tasks give all tasks created by this user.
  has_many :final_review_tasks, class_name: 'Task', foreign_key: 'final_reviewer_id'   #change
  has_many :comments
  has_many :notifications, foreign_key: 'recipient_id'
  has_many :assigned_action_nodes, class_name: 'ActionNode', foreign_key: 'reviewer_id'

  validates :email, presence: true, uniqueness: true
  validates :first_name, presence: true
  validates :password_digest, presence: true
  validates :role, presence: true

  def full_name
    "#{first_name} #{last_name}"
  end
end
