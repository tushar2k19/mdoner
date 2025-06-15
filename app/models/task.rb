class Task < ApplicationRecord
  acts_as_paranoid
  belongs_to :editor, class_name: 'User'
  belongs_to :reviewer, class_name: 'User', optional: true
  # belongs_to :final_reviewer, class_name: 'User', optional: true
  has_many :versions, class_name: 'TaskVersion', dependent: :destroy
  belongs_to :current_version, class_name: 'TaskVersion', optional: true

  # has_many :comments, dependent: :destroy
  # has_many :notifications, dependent: :destroy
  has_many :reviews, through: :versions


  # before_save :highlight_dates_in_content

  enum status: {
    draft: 0,
    under_review: 1,
    # final_review: 2,
    approved: 3,
    completed: 4
  }

  validates :sector_division, :description, :action_to_be_taken,
            :original_date, :responsibility, :review_date, presence: true

  # Sanitize HTML from TinyMCE but allow certain tags and attributes
  before_save :sanitize_content

  scope :active_for_date, ->(date) {
    where('DATE(created_at) <= ?', date)   #scope :truly_active, -> { where.not(status: 'completed') }
  }

  scope :completed_till_date, ->(date) {
    where('DATE(completed_at) <= ?', date)
  }
  def current_content
    current_version&.action_nodes || []
  end

  private
  def sanitize_content
    self.action_to_be_taken = ActionController::Base.helpers.sanitize(
      action_to_be_taken,
      tags: %w[p br div span b i u ul ol li table tr td th strong em font],
      attributes: %w[style class color align]
    )
  end

  def highlight_dates_in_content
    return unless action_to_be_taken.present?

    self.action_to_be_taken = action_to_be_taken.gsub(
      /(\d{1,2}\/\d{1,2}(?:\/\d{2,4})?)/,
      '<span style="background-color: yellow">\1</span>'
    )
  end
end
