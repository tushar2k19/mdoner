# frozen_string_literal: true

require "test_helper"

class MeetingPackNotificationDispatcherTest < ActiveSupport::TestCase
  include ActiveJob::TestHelper

  def setup
    super
    clear_enqueued_jobs
    @user = build_user(role: :reviewer, first_name: "Notify", last_name: "Target")
  end

  def teardown
    clear_enqueued_jobs
    super
  end

  test "email channel enqueues email job" do
    previous = ENV["ENABLE_NOTIFICATION_EMAILS"]
    ENV["ENABLE_NOTIFICATION_EMAILS"] = "true"
    assert_enqueued_with(job: MeetingPackNotificationEmailJob) do
      MeetingPackNotificationDispatcher.deliver!(
        user_id: @user.id,
        kind: MeetingPackNotification::KIND_PACK_ASSIGNMENT_CREATED,
        body: "Body",
        payload: { "node_label" => "1(a)(i)" },
        channels: %i[in_app email]
      )
    end
  ensure
    ENV["ENABLE_NOTIFICATION_EMAILS"] = previous
  end

  test "default in_app only does not enqueue email job" do
    assert_enqueued_jobs 0, only: MeetingPackNotificationEmailJob do
      MeetingPackNotificationDispatcher.deliver!(
        user_id: @user.id,
        kind: MeetingPackNotification::KIND_PACK_ASSIGNMENT_CREATED,
        body: "Body",
        payload: { "node_label" => "1(a)(i)" }
      )
    end
  end

  test "dedupe key prevents duplicate enqueue" do
    dedupe_key = "dedupe-key"

    previous = ENV["ENABLE_NOTIFICATION_EMAILS"]
    ENV["ENABLE_NOTIFICATION_EMAILS"] = "true"
    assert_enqueued_jobs 1, only: MeetingPackNotificationEmailJob do
      first = MeetingPackNotificationDispatcher.deliver!(
        user_id: @user.id,
        kind: MeetingPackNotification::KIND_PACK_ASSIGNMENT_CREATED,
        body: "Body",
        payload: {},
        dedupe_key: dedupe_key,
        channels: %i[in_app email]
      )
      second = MeetingPackNotificationDispatcher.deliver!(
        user_id: @user.id,
        kind: MeetingPackNotification::KIND_PACK_ASSIGNMENT_CREATED,
        body: "Body",
        payload: {},
        dedupe_key: dedupe_key,
        channels: %i[in_app email]
      )

      assert first.present?
      assert_nil second
    end
  ensure
    ENV["ENABLE_NOTIFICATION_EMAILS"] = previous
  end
end
