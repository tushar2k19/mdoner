# frozen_string_literal: true

class NewMeetingSchedule < ApplicationRecord
  acts_as_paranoid

  belongs_to :current_new_dashboard_version, class_name: "NewDashboardVersion", inverse_of: :new_meeting_schedules
  belongs_to :set_by_user, class_name: "User"
  has_many :new_meeting_schedule_events, dependent: :destroy

  validates :meeting_date, :set_at, presence: true
end
