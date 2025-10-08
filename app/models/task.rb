class Task < ApplicationRecord
  acts_as_paranoid
  belongs_to :editor, class_name: 'User'
  belongs_to :reviewer, class_name: 'User', optional: true
  # belongs_to :final_reviewer, class_name: 'User', optional: true
  has_many :versions, class_name: 'TaskVersion', dependent: :destroy
  belongs_to :current_version, class_name: 'TaskVersion', optional: true

  # has_many :comments, dependent: :destroy
  has_many :notifications, dependent: :destroy
  has_many :reviews, through: :versions
  has_many :task_tags, dependent: :destroy
  has_many :tags, through: :task_tags
  
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

  # Get reviewer information for the task
  def reviewer_info
    return nil unless current_version
    
    reviewers = current_version.all_action_nodes
                              .joins(:reviewer)
                              .select('DISTINCT users.first_name, users.last_name')
                              .reorder('users.first_name, users.last_name')
                              .map { |node| "#{node.first_name} #{node.last_name}" }
    
    reviewers.any? ? reviewers.join(', ') : nil
  end

  # Update task's review_date based on nearest review_date from all nodes
  def update_review_date_from_nodes
    return unless current_version&.all_action_nodes&.any?

    # Find the nearest (earliest) review_date from all nodes
    nearest_date = current_version.all_action_nodes
                                  .where.not(review_date: nil)
                                  .minimum(:review_date)

    if nearest_date && nearest_date != review_date
      update_column(:review_date, nearest_date)
      Rails.logger.info "Updated task #{id} review_date to #{nearest_date}"
    end
  end

  # Custom destroy method to handle foreign key constraints
  def destroy
    ActiveRecord::Base.transaction do
      # Clear current_version_id first to avoid foreign key constraint
      if current_version_id
        # Use update_column to bypass validations and callbacks
        self.update_column(:current_version_id, nil)
      end
      
      # Delete all notifications first to prevent foreign key constraint violations
      # This includes both task notifications and review notifications
      all_notification_ids = []
      
      # Collect direct task notifications
      all_notification_ids += notifications.pluck(:id)
      
      # Collect review notifications from all task versions
      versions.includes(:reviews).each do |version|
        version.reviews.each do |review|
          all_notification_ids += review.notifications.pluck(:id)
        end
      end
      
      # Delete all notifications at once using raw SQL to avoid constraint issues
      if all_notification_ids.any?
        Notification.where(id: all_notification_ids.uniq).delete_all
      end
      
      version_ids = versions.pluck(:id)
      if version_ids.any?
        TaskVersion.where(base_version_id: version_ids).update_all(base_version_id: nil)
        Review.where(base_version_id: version_ids).update_all(base_version_id: nil)
      end
      
      comment_trail_ids = []
      versions.includes(reviews: :comment_trail).each do |version|
        version.reviews.each do |review|
          if review.comment_trail
            comment_trail_ids << review.comment_trail.id
          end
        end
      end
      
      # Also find any orphaned comments that might reference comment_trails we're about to delete
      if comment_trail_ids.any?
        Comment.where(comment_trail_id: comment_trail_ids.uniq).delete_all
      end
      
      # Temporarily disable foreign key checks for MySQL during destruction
      ActiveRecord::Base.connection.execute("SET FOREIGN_KEY_CHECKS = 0")
      
      begin
        # Then destroy all versions (which will cascade to reviews, comment_trails, comments, action_nodes)
        self.versions.destroy_all
        # Finally destroy the task itself
        super
      ensure
        # Re-enable foreign key checks
        ActiveRecord::Base.connection.execute("SET FOREIGN_KEY_CHECKS = 1")
      end
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
