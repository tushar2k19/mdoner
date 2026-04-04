# frozen_string_literal: true

class NewDashboardAssignment < ApplicationRecord
  acts_as_paranoid

  belongs_to :new_dashboard_version
  belongs_to :new_dashboard_snapshot_action_node
  belongs_to :user
end
