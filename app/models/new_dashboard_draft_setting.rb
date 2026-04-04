# frozen_string_literal: true

class NewDashboardDraftSetting < ApplicationRecord
  belongs_to :updated_by, class_name: "User", optional: true

  validates :singleton_key, presence: true, uniqueness: true

  GLOBAL_KEY = "global"

  def self.global
    find_or_create_by!(singleton_key: GLOBAL_KEY) do |row|
      row.target_meeting_date = Date.current
    end
  end
end
