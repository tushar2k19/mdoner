class Task < ApplicationRecord
  belongs_to :editor, class_name: 'User'
  belongs_to :reviewer, class_name: 'User', optional: true
  belongs_to :final_reviewer, class_name: 'User', optional: true

  has_many :comments, dependent: :destroy
  has_many :notifications, dependent: :destroy

  enum status: {
    draft: 0,
    under_review: 1,
    final_review: 2,
    approved: 3,
    completed: 4
  }

  validates :sector_division, :description, :action_to_be_taken,
            :original_date, :responsibility, :review_date, presence: true

  # Sanitize HTML from TinyMCE but allow certain tags and attributes
  before_save :sanitize_content

  scope :active_for_date, ->(date) {
    where('DATE(created_at) <= ? AND completed_at IS NULL', date)
  }

  scope :completed_for_date, ->(date) {
    where('DATE(completed_at) = ?', date)
  }

  scope :for_reviewer, ->(user_id) {
    where(reviewer_id: user_id)
  }

  scope :for_final_reviewer, ->(user_id) {
    where(final_reviewer_id: user_id)
  }

  private

  def sanitize_content
    self.action_to_be_taken = ActionController::Base.helpers.sanitize(
      action_to_be_taken,
      tags: %w[p br div span b i u ul ol li table tr td th strong em font],
      attributes: %w[style class color align]
    )
  end
end
