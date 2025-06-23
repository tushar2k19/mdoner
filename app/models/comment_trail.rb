# app/models/comment_trail.rb
class CommentTrail < ApplicationRecord
  belongs_to :review
  has_many :comments, dependent: :destroy

  # Get task through review's task_version
  def task
    review.task_version.task
  end

  # Get all unresolved comments in this trail
  def unresolved_comments
    comments.where(resolved: false)
  end

  # Check if all comments in this trail are resolved
  def all_comments_resolved?
    comments.exists? && unresolved_comments.empty?
  end

  # Get the latest comment in this trail
  def latest_comment
    comments.order(created_at: :desc).first
  end
end
