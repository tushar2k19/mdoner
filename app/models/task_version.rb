# app/models/task_version.rb
class TaskVersion < ApplicationRecord
  belongs_to :task
  belongs_to :editor, class_name: 'User'
  belongs_to :base_version, class_name: 'TaskVersion', optional: true
  # has_many :action_nodes, dependent: :destroy
  has_many :action_nodes, -> { where(parent_id: nil) }, dependent: :destroy
  has_many :all_action_nodes, class_name: 'ActionNode', dependent: :destroy
  has_many :reviews, dependent: :destroy

  enum status: {
    draft: 'draft',
    under_review: 'under_review',
    approved: 'approved',
    completed: 'completed'
  }
  def create_new_draft(editor)
    new_version = task.versions.create!(
      editor: editor,
      base_version: self,
      version_number: task.versions.count + 1,
      status: :draft
    )

    # Deep copy action nodes
    action_nodes.each do |node|
      node.copy_to_version(new_version)
    end

    new_version
  end

  # Gets all reviewers involved (for notifications)
  def all_reviewers
    reviews.map(&:reviewer).uniq
  end
end
