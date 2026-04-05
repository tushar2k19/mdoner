# frozen_string_literal: true

# Audit row when a living draft NewActionNode review_date moves to a later calendar day
# and the client supplies review_date_extension (meeting dashboard PUT .../nodes/:id).
class NewReviewDateExtensionEvent < ApplicationRecord
  belongs_to :new_task
  belongs_to :new_action_node, class_name: "NewActionNode", optional: true
  belongs_to :recorded_by, class_name: "User"

  validates :reason, presence: true, inclusion: { in: ReviewDateExtensionCodes::REASON_CODES }
  validates :previous_review_date, :new_review_date, presence: true
  validate :new_date_after_previous

  validates :explanation,
            length: { maximum: ReviewDateExtensionCodes::MAX_EXPLANATION_LENGTH },
            allow_blank: true

  private

  def new_date_after_previous
    return if previous_review_date.blank? || new_review_date.blank?
    return if new_review_date > previous_review_date

    errors.add(:new_review_date, "must be after previous review date")
  end
end
