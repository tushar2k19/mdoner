class NotificationDispatcher
  def deliver(recipient_id, kind, message, task_id: nil, new_task_id: nil, review_id: nil, payload: {})
    notification = Notification.create!(
      recipient_id: recipient_id,
      notification_type: kind,
      message: message,
      task_id: task_id,
      new_task_id: new_task_id,
      review_id: review_id,
      payload: payload
    )

    broadcast(notification)
    notification
  end

  private

  def broadcast(notification)
    REDIS.publish(
      "notifications_stream_#{notification.recipient_id}",
      {
        id: notification.id,
        message: notification.message,
        task_id: notification.task_id,
        new_task_id: notification.new_task_id,
        notification_type: notification.notification_type,
        created_at: notification.created_at,
        read: notification.read,
        payload: notification.payload
      }.to_json
    )
  rescue Redis::CannotConnectError => e
    Rails.logger.error("Redis connection failed for broadcasting notification: #{e.message}")
  end
end
