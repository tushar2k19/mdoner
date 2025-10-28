class TaskTag < ApplicationRecord
  belongs_to :task
  belongs_to :tag
  belongs_to :created_by, class_name: 'User', optional: true

  validates :task_id, uniqueness: { scope: :tag_id }
end