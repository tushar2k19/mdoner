# frozen_string_literal: true

class MeetingPackNotificationsController < ApplicationController
  include ActionController::Live

  before_action :authenticate_stream, only: [:stream]
  before_action :authorize_access_request!, except: [:stream]

  LIMIT = 100

  def index
    rows = current_user.meeting_pack_notifications.recent_first.limit(LIMIT)
    render json: rows.map { |n| serialize_notification(n) }
  end

  def mark_read
    n = current_user.meeting_pack_notifications.find(params[:id])
    n.mark_read!
    render json: { success: true, notification: serialize_notification(n) }
  end

  def mark_all_read
    current_user.meeting_pack_notifications.unread.update_all(read_at: Time.current)
    render json: { success: true }
  end

  def stream
    response.headers["Content-Type"] = "text/event-stream"
    response.headers["Cache-Control"] = "no-cache"
    response.headers["X-Accel-Buffering"] = "no"
    response.headers["Connection"] = "keep-alive"
    response.headers["Last-Modified"] = Time.now.httpdate

    channel = RedisPubSubChannel.namespaced_channel("meeting_notifications_stream_#{current_user.id}")
    Sse::RedisStream.new(
      response: response,
      channel: channel,
      user_id: current_user.id,
      kind: "meeting_notifications"
    ).run
  rescue IOError, ActionController::Live::ClientDisconnected
    # Client closed the connection. Stream helper handles full cleanup.
  end

  private

  def authenticate_stream
    if params[:token].present?
      request.headers["Authorization"] = "Bearer #{params[:token]}"
    end
    authorize_access_request!
  end

  def serialize_notification(n)
    {
      id: n.id,
      kind: n.kind,
      body: n.body,
      read_at: n.read_at&.iso8601,
      created_at: n.created_at.iso8601,
      payload: n.payload
    }
  end
end
