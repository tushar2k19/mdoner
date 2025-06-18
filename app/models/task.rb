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
  
  # Handle deletion properly
  # before_destroy :clear_current_version_and_versions


  # before_save :highlight_dates_in_content

  enum status: {
    draft: 0,
    under_review: 1,
    # final_review: 2,
    approved: 3,
    completed: 4
  }

  validates :sector_division, :description, :original_date, :responsibility, :review_date, presence: true

  scope :active_for_date, ->(date) {
    where('DATE(created_at) <= ?', date)
  }

  scope :completed_till_date, ->(date) {
    where('DATE(completed_at) <= ?', date)
  }
  
  def current_content
    current_version&.action_nodes || []
  end

  # Get formatted content from current version's nodes
  def action_to_be_taken
    current_version&.html_formatted_content || ''
  end

  # Custom destroy method to handle foreign key constraints
  def destroy
    ActiveRecord::Base.transaction do
      # Clear current_version_id first to avoid foreign key constraint
      if current_version_id
        # Use update_column to bypass validations and callbacks
        self.update_column(:current_version_id, nil)
      end
      # Then destroy all versions (which will cascade to action_nodes)
      self.versions.destroy_all
      # Finally destroy the task itself
      super
    end
  end

  private

  def clear_current_version_and_versions
    ActiveRecord::Base.transaction do
      # Clear current_version_id first to avoid foreign key constraint
      if current_version_id
        # Use update_column to bypass validations and callbacks
        self.update_column(:current_version_id, nil)
      end
      # Then destroy all versions (which will cascade to action_nodes)
      # Use destroy_all to handle in a single transaction
      self.versions.destroy_all
    end
  end
end
