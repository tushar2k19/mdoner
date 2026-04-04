# frozen_string_literal: true

class NewTaskTag < ApplicationRecord
  belongs_to :new_task
  belongs_to :tag
  belongs_to :created_by, class_name: "User", optional: true

  validates :new_task_id, uniqueness: { scope: :tag_id }
end
