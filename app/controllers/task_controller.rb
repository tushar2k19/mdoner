class TaskController < ApplicationController
  # before_action :authorize_access_request!
  before_action :set_task, only: [
    :update,
    :destroy,
    :send_for_review,
    :approve,
  ]
  def index
    date = params[:date] ? Date.parse(params[:date]) : Date.today
    base_query = Task.includes(:editor, :reviewer, :final_reviewer)

    active_tasks = case current_user.role
                   when 'editor'
                     base_query.active_for_date(date)
                   when 'reviewer'
                     base_query.active_for_date(date)
                               .where(reviewer_id: current_user.id)
                               .where(status: ['under_review', 'changes_requested'])
                   when 'final_reviewer'
                     base_query.active_for_date(date)
                               .where(final_reviewer_id: current_user.id)
                               .where(status: 'final_review')
                   end.order(created_at: :desc)

    completed_tasks = case current_user.role
                      when 'editor'
                        base_query.completed_for_date(date)
                      when 'reviewer'
                        base_query.completed_for_date(date)
                                  .where(reviewer_id: current_user.id)
                      when 'final_reviewer'
                        base_query.completed_for_date(date)
                                  .where(final_reviewer_id: current_user.id)
                      end.order(completed_at: :desc)

    render json: {
      active: active_tasks,
      completed: completed_tasks
    }
  end

  def approved_tasks
    date = params[:date] ? Date.parse(params[:date]) : Date.today
    base_query = Task.includes(:editor, :reviewer, :final_reviewer)
                     .where(status: :approved)
                     .where('DATE(updated_at) <= ?', date)
                     .where(completed_at: nil)

    tasks = case current_user.role
            when 'editor'
              base_query
            when 'reviewer'
              base_query.where(reviewer_id: current_user.id)
            when 'final_reviewer'
              base_query.where(final_reviewer_id: current_user.id)
            end.order(updated_at: :desc)

    render json: { tasks: tasks }
  end

  def completed_tasks
    date = params[:date] ? Date.parse(params[:date]) : Date.today
    base_query = Task.includes(:editor, :reviewer, :final_reviewer)
                     .where.not(completed_at: nil)
                     .where('DATE(completed_at) <= ?', date)

    tasks = case current_user.role
            when 'editor'
              base_query
            when 'reviewer'
              base_query.where(reviewer_id: current_user.id)
            when 'final_reviewer'
              base_query.where(final_reviewer_id: current_user.id)
            end.order(completed_at: :desc)

    render json: { tasks: tasks }
  end

  def create
    task = current_user.created_tasks.build(task_params)

    if task.save
      render json: { success: true, data: task }
    else
      render json: { error: task.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @task.update(task_params)
      if @task.approved? && task_params[:status] != 'approved'
        @task.update(status: :draft, reviewer_id: nil, final_reviewer_id: nil)
      end
      render json: { success: true, data: @task }
    else
      render json: { error: @task.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    pp"task = #{@task}, @task.editor = #{@task.editor}, current_user = #{current_user}"
    if  @task #current_user == @task.editor && @task.draft?
      @task.destroy
      render json: { success: true }
    else
      render json: { error: 'Unauthorized to delete this task' }, status: :unauthorized
    end
  end

  def send_for_review
    reviewer = User.find(params[:reviewer_id])

    if @task.update(reviewer: reviewer, status: :under_review)
      Notification.create(
        recipient: reviewer,
        task: @task,
        message: "New task '#{@task.description}' requires your review",
        notification_type: :review_request
      )
      render json: { success: true }
    else
      render json: { error: 'Unable to send for review' }, status: :unprocessable_entity
    end
  end

  # def approve
  #   case current_user.role
  #   when 'reviewer'
  #     if @task.under_review?
  #       @task.update(status: :final_review)
  #       notify_final_reviewer
  #       render json: { success: true, message: 'Task sent for final review' }
  #     else
  #       render json: { error: 'Invalid task status' }, status: :unprocessable_entity
  #     end
  #   when 'final_reviewer'
  #     if @task.final_review?
  #       @task.update(status: :approved)
  #       notify_approval
  #       render json: { success: true, message: 'Task approved' }
  #     else
  #       render json: { error: 'Invalid task status' }, status: :unprocessable_entity
  #     end
  #   else
  #     render json: { error: 'Unauthorized' }, status: :unauthorized
  #   end
  # end
  def approve
    case current_user.role
    when 'reviewer'
      if @task.under_review?
        # Instead of moving to final review, directly complete the task
        if @task.update(
          status: :completed,
          completed_at: Time.current,
          final_reviewer_id: @task.reviewer_id  # Set final_reviewer to same as reviewer
        )
          notify_task_completion
          render json: { success: true, message: 'Task approved' }
        else
          render json: { error: 'Unable to approve task' }, status: :unprocessable_entity
        end
      else
        render json: { error: 'Invalid task status' }, status: :unprocessable_entity
      end
    else
      render json: { error: 'Unauthorized' }, status: :unauthorized
    end
  end

  private

  def notify_task_completion
    # Notify all relevant parties about task completion
    [@task.editor, @task.reviewer].compact.each do |user|
      Notification.create(
        recipient: user,
        task: @task,
        message: "Task '#{@task.description}' has been approved",
        notification_type: :task_completed
      )
    end
  end

  def complete
    if @task.update(completed_at: Time.current, status: :completed)
      notify_completion
      render json: { success: true }
    else
      render json: { error: 'Unable to mark task as complete' }, status: :unprocessable_entity
    end
  end

  def mark_incomplete
    if @task.update(
      status: :draft,
      reviewer_id: nil,
      final_reviewer_id: nil,
      completed_at: nil
    )
      notify_incomplete
      render json: { success: true }
    else
      render json: { error: 'Unable to mark task as incomplete' }, status: :unprocessable_entity
    end
  end

  private

  def set_task
    @task = Task.find(params[:id])
  end

  def task_params
    params.require(:task).permit(
      :sector_division,
      :description,
      :action_to_be_taken,
      :original_date,
      :responsibility,
      :review_date,
      :status
    )
  end

  def notify_final_reviewer
    Notification.create(
      recipient: @task.final_reviewer,
      task: @task,
      message: "Task '#{@task.description}' needs final review",
      notification_type: :review_request
    )
  end

  def notify_approval
    [@task.editor, @task.reviewer].each do |user|
      Notification.create(
        recipient: user,
        task: @task,
        message: "Task '#{@task.description}' has been approved",
        notification_type: :task_approved
      )
    end
  end

  def notify_completion
    [@task.editor, @task.reviewer, @task.final_reviewer].compact.each do |user|
      Notification.create(
        recipient: user,
        task: @task,
        message: "Task '#{@task.description}' has been marked as completed",
        notification_type: :task_completed
      )
    end
  end

  def notify_incomplete
    [@task.editor, @task.reviewer, @task.final_reviewer].compact.each do |user|
      Notification.create(
        recipient: user,
        task: @task,
        message: "Task '#{@task.description}' has been marked as incomplete and needs review",
        notification_type: :task_approved
      )
    end
  end
end
