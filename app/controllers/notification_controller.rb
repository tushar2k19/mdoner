class NotificationController < ApplicationController
  # before_action :authorize_access_request!

  def index
    notifications = current_user.notifications
                                .includes(:task)
                                .order(created_at: :desc)
                                .limit(50)

    render json: notifications.map { |notification| notification_json(notification) }
  end

  def mark_as_read
    notification = current_user.notifications.find(params[:id])
    notification.update(read: true)

    # Return redirect information based on notification type
    redirect_info = get_redirect_info(notification)

    render json: { 
      success: true,
      redirect: redirect_info
    }
  end

  def mark_all_as_read
    current_user.notifications.update_all(read: true)
    render json: { success: true }
  end

  private

  def get_redirect_info(notification)
    # Partial approval: multiple reviews per version — send editor to the hub, not the
    # single review row that was just approved (which would feel "stuck" or empty).
    if notification.partial_approval?
      return { type: 'task_review_hub', task_id: notification.task_id }
    end

    if notification.review_id.present?
      { type: 'review', id: notification.review_id }
    else
      latest_review = notification.task.reviews.order(created_at: :desc).first
      if latest_review
        { type: 'review', id: latest_review.id }
      else
        { type: 'task', id: notification.task_id }
      end
    end
  end

  def notification_json(notification)
    {
      id: notification.id,
      message: notification.message,
      task_id: notification.task_id,
      review_id: notification.review_id,
      read: notification.read,
      created_at: notification.created_at,
      notification_type: notification.notification_type
    }
  end
end

