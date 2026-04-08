# frozen_string_literal: true

require "test_helper"

class MeetingPackNotificationEmailJobTest < ActiveJob::TestCase
  def setup
    super
    @user = build_user(role: :reviewer, first_name: "Mail", last_name: "User")
    @notification = MeetingPackNotification.create!(
      user_id: @user.id,
      kind: MeetingPackNotification::KIND_PACK_ASSIGNMENT_CREATED,
      body: "Editor needs inputs from you on Node 1(a)(i). Click to respond now.",
      payload: {
        "node_label" => "1(a)(i)",
        "new_dashboard_version_id" => 5,
        "stable_node_id" => "sn-1",
        "new_task_id" => 22
      }
    )
  end

  test "uses demo recipient override and marks emailed_at" do
    captured = nil
    fake_client = Object.new
    fake_client.define_singleton_method(:send_email!) do |**kwargs|
      captured = kwargs
      { "id" => "email_123" }
    end

    with_env(
      "ENABLE_NOTIFICATION_EMAILS" => "true",
      "DEMO_NOTIFICATION_EMAIL_TO" => "demo@recipient.test",
      "RESEND_EMAIL_FROM" => "onboarding@resend.dev",
      "FRONTEND_APP_URL" => "http://localhost:8080"
    ) do
      with_singleton_method(ResendClient, :new, ->(*_args) { fake_client }) do
        MeetingPackNotificationEmailJob.perform_now(@notification.id)
      end
    end

    @notification.reload
    assert @notification.emailed_at.present?
    assert_equal "demo@recipient.test", captured[:to]
    assert_equal "onboarding@resend.dev", captured[:from]
    assert_includes captured[:text], "focus_node=sn-1"
    assert_includes captured[:html], "MDONER Dashboard"
    assert_includes captured[:html], "Open Final Dashboard"
  end

  test "does nothing when already emailed" do
    @notification.update!(emailed_at: Time.current)

    fake_client = Object.new
    fake_client.define_singleton_method(:send_email!) do |**_kwargs|
      raise "should not send"
    end

    with_env("ENABLE_NOTIFICATION_EMAILS" => "true") do
      with_singleton_method(ResendClient, :new, ->(*_args) { fake_client }) do
        MeetingPackNotificationEmailJob.perform_now(@notification.id)
      end
    end
  end

  test "renders kind-specific subject and template copy for reminder and comments" do
    reminder = MeetingPackNotification.create!(
      user_id: @user.id,
      kind: MeetingPackNotification::KIND_HUB_REMINDER_PENDING,
      body: "Inputs still PENDING on Node 2(a). Click to respond now.",
      payload: {
        "node_label" => "2(a)",
        "new_dashboard_version_id" => 5,
        "stable_node_id" => "sn-reminder",
        "new_task_id" => 22
      }
    )
    comments = MeetingPackNotification.create!(
      user_id: @user.id,
      kind: MeetingPackNotification::KIND_DASHBOARD_NODE_COMMENT_FOR_ASSIGNEES,
      body: "New comments added on Node 2(a). Check now!!",
      payload: {
        "node_label" => "2(a)",
        "new_dashboard_version_id" => 5,
        "stable_node_id" => "sn-comment",
        "new_task_id" => 22
      }
    )

    reminder_capture = nil
    comment_capture = nil
    fake_client = Object.new
    fake_client.define_singleton_method(:send_email!) do |**kwargs|
      if kwargs[:subject].include?("Reminder:")
        reminder_capture = kwargs
      elsif kwargs[:subject].include?("New comment update")
        comment_capture = kwargs
      end
      { "id" => "email_123" }
    end

    with_env(
      "ENABLE_NOTIFICATION_EMAILS" => "true",
      "DEMO_NOTIFICATION_EMAIL_TO" => "demo@recipient.test",
      "RESEND_EMAIL_FROM" => "onboarding@resend.dev",
      "FRONTEND_APP_URL" => "https://mdoner.netlify.app/login"
    ) do
      with_singleton_method(ResendClient, :new, ->(*_args) { fake_client }) do
        MeetingPackNotificationEmailJob.perform_now(reminder.id)
        MeetingPackNotificationEmailJob.perform_now(comments.id)
      end
    end

    assert reminder_capture.present?
    assert comment_capture.present?
    assert_includes reminder_capture[:subject], "Reminder: pending inputs"
    assert_includes comment_capture[:subject], "New comment update"
    assert_includes reminder_capture[:html], "Published Version"
    assert_includes comment_capture[:html], "/new-final?"
    refute_includes comment_capture[:html], "/login/new-final?"
  end

  private

  def with_env(vars)
    previous = {}
    vars.each do |k, v|
      previous[k] = ENV[k]
      ENV[k] = v
    end
    yield
  ensure
    previous.each { |k, v| ENV[k] = v }
  end

  def with_singleton_method(target, method_name, replacement)
    singleton = target.singleton_class
    original = singleton.instance_method(method_name) if singleton.method_defined?(method_name)
    singleton.send(:define_method, method_name, &replacement)
    yield
  ensure
    if original
      singleton.send(:define_method, method_name, original)
    else
      singleton.send(:remove_method, method_name)
    end
  end
end
