# frozen_string_literal: true

class MeetingPackNotification < ApplicationRecord
  belongs_to :user

  KIND_PACK_ASSIGNMENT_CREATED = "pack_assignment_created"
  KIND_DASHBOARD_NODE_COMMENT_FOR_ASSIGNEES = "dashboard_node_comment_for_assignees"
  KIND_HUB_REMINDER_PENDING = "hub_reminder_pending"
  KIND_DASHBOARD_NODE_COMMENT_FOR_EDITORS = "dashboard_node_comment_for_editors"
  KIND_MEETING_PLACEHOLDER_E2 = "meeting_placeholder_e2"

  KINDS = [
    KIND_PACK_ASSIGNMENT_CREATED,
    KIND_DASHBOARD_NODE_COMMENT_FOR_ASSIGNEES,
    KIND_HUB_REMINDER_PENDING,
    KIND_DASHBOARD_NODE_COMMENT_FOR_EDITORS,
    KIND_MEETING_PLACEHOLDER_E2
  ].freeze

  validates :kind, presence: true, inclusion: { in: KINDS }
  validates :body, presence: true

  scope :unread, -> { where(read_at: nil) }
  scope :recent_first, -> { order(created_at: :desc) }

  def mark_read!
    update!(read_at: Time.current) if read_at.nil?
  end
end
