# frozen_string_literal: true

class MeetingHubReminderCooldown < ApplicationRecord
  belongs_to :editor, class_name: "User"
  belongs_to :new_dashboard_version, class_name: "NewDashboardVersion"
end
