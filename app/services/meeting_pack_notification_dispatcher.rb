# frozen_string_literal: true

# Persists meeting-workflow notifications and pushes to an isolated Redis SSE channel
# (`meeting_notifications_stream_<user_id>`). Optional channels: `:in_app`, `:email`.
class MeetingPackNotificationDispatcher
  def self.deliver!(user_id:, kind:, body:, payload: {}, dedupe_key: nil, channels: [:in_app])
    selected_channels = normalize_channels(channels)

    attrs = {
      user_id: user_id,
      kind: kind,
      body: body,
      payload: payload.deep_stringify_keys,
      dedupe_key: dedupe_key
    }.compact

    notification = MeetingPackNotification.create!(attrs)
    new.broadcast(notification) if selected_channels.include?(:in_app)
    if selected_channels.include?(:email)
      if MeetingPackNotificationEmailJob.email_delivery_enabled?
        Rails.logger.info("[meeting_email] enqueue notification_id=#{notification.id} kind=#{notification.kind} user_id=#{notification.user_id}")
        MeetingPackNotificationEmailJob.perform_later(notification.id)
      else
        Rails.logger.info("[meeting_email] skipped (disabled) notification_id=#{notification.id} kind=#{notification.kind} user_id=#{notification.user_id}")
      end
    end
    notification
  rescue ActiveRecord::RecordNotUnique
    # duplicate dedupe_key for same user (e.g. reminder replay)
    nil
  end

  def self.normalize_channels(channels)
    values = Array(channels).map { |c| c.to_sym }.uniq
    allowed = %i[in_app email]
    return [:in_app] if values.empty?
    raise ArgumentError, "unsupported channels" unless (values - allowed).empty?

    values
  end

  def broadcast(notification)
    REDIS.publish(
      "meeting_notifications_stream_#{notification.user_id}",
      sse_payload(notification).to_json
    )
  rescue Redis::CannotConnectError => e
    Rails.logger.error("Redis failed for meeting notification broadcast: #{e.message}")
  end

  def sse_payload(notification)
    {
      meeting_notification: true,
      id: notification.id,
      kind: notification.kind,
      body: notification.body,
      read_at: notification.read_at&.iso8601,
      created_at: notification.created_at.iso8601,
      payload: notification.payload
    }
  end
end
