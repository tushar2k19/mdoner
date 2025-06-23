class CommentController < ApplicationController
  # before_action :authorize_access_request!
  before_action :set_task, except: [:add_comment_to_review, :resolve_comment, :update_review_comment, :delete_review_comment]
  before_action :set_comment, only: [:update, :destroy]

  def index
    comments = @task.comments.includes(:user).order(created_at: :desc)
    render json: comments.map { |comment| comment_json(comment) }
  end

  # New method: Get comment trails for a task
  def comment_trails
    # Get all reviews for this task
    reviews = Review.joins(:task_version)
                   .where(task_versions: { task_id: @task.id })
                   .includes(:reviewer, :comment_trail)
                   .order(created_at: :desc)

    trails = reviews.map do |review|
      trail = review.comment_trail
      next unless trail # Skip reviews without comment trails

      {
        id: trail.id,
        created_at: trail.created_at,
        review: {
          id: review.id,
          status: review.status,
          summary: review.summary,
          reviewer_name: review.reviewer&.full_name,
          created_at: review.created_at
        },
        comments: trail.comments.includes(:user).order(created_at: :asc).map do |comment|
          {
            id: comment.id,
            content: comment.content,
            user_name: comment.user.full_name,
            created_at: comment.created_at,
            resolved: comment.resolved
          }
        end
      }
    end.compact

    render json: { success: true, trails: trails }
  end

  # New method: Add comment to a specific review's trail
  def add_comment_to_review
    review = Review.find(params[:review_id])
    
    # Ensure the review has a comment trail
    trail = review.comment_trail || review.create_comment_trail!
    
    comment = trail.comments.build(
      content: params[:content],
      user: current_user,
      review_date: Date.current,
      action_node_id: params[:action_node_id]
    )

    if comment.save
      render json: {
        success: true,
        comment: {
          id: comment.id,
          content: comment.content,
          user_name: comment.user.full_name,
          user_id: comment.user.id,
          created_at: comment.created_at,
          resolved: comment.resolved,
          action_node_id: comment.action_node_id,
          references_node: comment.references_node?,
          referenced_node: comment.references_node? ? {
            content: comment.referenced_node_content,
            counter: comment.referenced_node_counter,
            exists: comment.referenced_node_exists?
          } : nil
        }
      }
    else
      render json: {
        success: false,
        errors: comment.errors.full_messages
      }, status: :unprocessable_entity
    end
  end

  # New method: Resolve a comment
  def resolve_comment
    comment = Comment.find(params[:comment_id])
    
    # Toggle the resolved status
    comment.resolved = !comment.resolved
    
    if comment.save
      render json: { 
        success: true,
        resolved: comment.resolved
      }
    else
      render json: { 
        success: false, 
        error: comment.errors.full_messages 
      }, status: :unprocessable_entity
    end
  end

  # New method: Update a review comment
  def update_review_comment
    comment = Comment.find(params[:comment_id])
    
    # Check if current user is the comment author
    unless comment.user == current_user
      render json: { 
        success: false, 
        error: 'You can only edit your own comments' 
      }, status: :forbidden
      return
    end
    
    if comment.update(content: params[:content])
      render json: {
        success: true,
        comment: {
          id: comment.id,
          content: comment.content,
          user_name: comment.user.full_name,
          user_id: comment.user.id,
          created_at: comment.created_at,
          resolved: comment.resolved,
          action_node_id: comment.action_node_id,
          references_node: comment.references_node?,
          referenced_node: comment.references_node? ? {
            content: comment.referenced_node_content,
            counter: comment.referenced_node_counter,
            exists: comment.referenced_node_exists?
          } : nil
        }
      }
    else
      render json: { 
        success: false, 
        errors: comment.errors.full_messages 
      }, status: :unprocessable_entity
    end
  end

  # New method: Delete a review comment
  def delete_review_comment
    comment = Comment.find(params[:comment_id])
    
    # Check if current user is the comment author
    unless comment.user == current_user
      render json: { 
        success: false, 
        error: 'You can only delete your own comments' 
      }, status: :forbidden
      return
    end
    
    if comment.destroy
      render json: { success: true }
    else
      render json: { 
        success: false, 
        error: 'Failed to delete comment' 
      }, status: :unprocessable_entity
    end
  end

  def add_comment_trail
    review_ids = Review.where(task_id: @task.id).pluck(:id)
    comments = CommentTrail.where(review_id: review_ids)
    show_list = comments.map  do |x|
      x.comment
    end
    render json: {success: true, comments: show_list}
  end

  def get_comment_trail
    review_ids = Review.where(task_id: @task.id).pluck(:id)
    comments = CommentTrail.where(review_id: review_ids)
    show_list = comments.pluck(:content)
    render json: {success: true, comments: show_list}
  end

  def update_comment_trail

  end

  def del_comment_trail

  end
  
  def create
    comment = @task.comments.build(comment_params.merge(user: current_user))

    if comment.save
      render json: comment_json(comment)
    else
      render json: { error: comment.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @comment.update(comment_params)
      render json: comment_json(@comment)
    else
      render json: { error: @comment.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    if @comment.destroy
      head :no_content
    else
      render json: { error: 'Failed to delete comment' }, status: :unprocessable_entity
    end
  end

  private

  def set_task
    @task = Task.find(params[:task_id])
  end
  
  def set_comment
    @comment = @task.comments.find(params[:id])
  end
  
  def comment_params
    params.require(:comment).permit(:content, :review_date)
  end

  def comment_json(comment)
    {
      id: comment.id,
      content: comment.content,
      user_name: comment.user.full_name,
      created_at: comment.created_at,
      review_date: comment.review_date
    }
  end
end
