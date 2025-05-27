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

    render json: { success: true }
  end

  def mark_all_as_read
    current_user.notifications.update_all(read: true)
    render json: { success: true }
  end

  private

  def notification_json(notification)
    {
      id: notification.id,
      message: notification.message,
      task_id: notification.task_id,
      read: notification.read,
      created_at: notification.created_at,
      notification_type: notification.notification_type
    }
  end
end

