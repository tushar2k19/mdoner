class Comment < ApplicationRecord
  acts_as_paranoid
  # belongs_to :task
  belongs_to :user
  belongs_to :comment_trail
  belongs_to :action_node, optional: true

  validates :content, presence: true
  validates :comment_trail, presence: true
  attribute :resolved, :boolean, default: false
  after_create :notify_relevant_users

  delegate :task, to: :comment_trail

  scope :resolved, -> { where(resolved: true) }
  scope :pending, -> { where(resolved: false) }
  
  # Check if this comment references a specific node
  def references_node?
    action_node_id.present?
  end
  
  # Get the referenced node content for display (like WhatsApp reply preview)
  def referenced_node_content
    return nil unless references_node? && action_node
    
    # Strip HTML tags for clean preview and limit length
    clean_content = strip_html_tags(action_node.content)
    clean_content.length > 100 ? "#{clean_content[0..97]}..." : clean_content
  end
  
  # Get the referenced node's display counter (1., a., i., etc.)
  def referenced_node_counter
    return nil unless references_node? && action_node
    action_node.display_counter
  end
  
  # Check if the referenced node still exists
  def referenced_node_exists?
    references_node? && action_node.present?
  end

  private
  
  def strip_html_tags(html_content)
    return '' unless html_content
    html_content.gsub(/<[^>]*>/, '').strip
  end

  def notify_relevant_users
    # relevant_users = [
    #   task.editor,
    #   task.reviewer,
    #   task.final_reviewer
    # ].compact.reject { |u| u == user }
    relevant_users = [comment_trail.review.task_version.editor] +
                 comment_trail.review.task_version.all_reviewers -
                 [user]
    relevant_users.each do |recipient|
      Notification.create(
        recipient: recipient,
        task: task,
        review: comment_trail.review,
        message: "New comment on task '#{task.description}' by #{user.full_name}",
        notification_type: 'comment'
      )
    end
  end
end
