class NotificationController < ApplicationController
  include ActionController::Live

  before_action :authenticate_stream, only: [:stream]
  before_action :authorize_access_request!, except: [:stream]

  def stream
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"
    response.headers["Connection"] = "keep-alive"
    # Helps Rack::ETag / some proxies avoid buffering the whole body (Rails Live doc).
    response.headers["Last-Modified"] = Time.now.httpdate

    channel = RedisPubSubChannel.namespaced_channel("notifications_stream_#{current_user.id}")
    Sse::RedisStream.new(
      response: response,
      channel: channel,
      user_id: current_user.id,
      kind: "legacy_notifications"
    ).run
  rescue IOError, ActionController::Live::ClientDisconnected
    # Client closed the connection. Stream helper handles full cleanup.
  end
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

  def authenticate_stream
    if params[:token].present?
      request.headers['Authorization'] = "Bearer #{params[:token]}"
    end
    authorize_access_request!
  end

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

