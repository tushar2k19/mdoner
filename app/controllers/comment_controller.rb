class CommentController < ApplicationController
  # before_action :authorize_access_request!
  before_action :set_task
  before_action :set_comment, only: [:update, :destroy]


  def index
    comments = @task.comments.includes(:user).order(created_at: :desc)
    render json: comments.map { |comment| comment_json(comment) }
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
