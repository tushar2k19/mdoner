class AddMultiReviewerSupportToReviews < ActiveRecord::Migration[7.1]
  def change
    add_column :reviews, :assigned_node_ids, :text, comment: "JSON array of ActionNode IDs assigned to this review"
    add_column :reviews, :reviewer_type, :string, default: 'task_level', comment: "Type of review: 'task_level' or 'node_level'"
    add_column :reviews, :is_aggregate_review, :boolean, default: false, comment: "True for task-level reviews that oversee multiple nodes"
    
    # Add index for performance
    add_index :reviews, :reviewer_type
    add_index :reviews, :is_aggregate_review
  end
end
