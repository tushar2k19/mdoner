# frozen_string_literal: true

class NewMeetingScheduleEvent < ApplicationRecord
  belongs_to :new_dashboard_version, optional: true
  belongs_to :new_meeting_schedule, optional: true
  belongs_to :actor, class_name: "User"

  validates :event_type, :actor, presence: true
end
