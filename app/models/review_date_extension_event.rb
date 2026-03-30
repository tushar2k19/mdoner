# frozen_string_literal: true

class ReviewDateExtensionEvent < ApplicationRecord
  REASON_CODES = %w[
    operational
    financial
    weather
    misc
    technical
    other
  ].freeze

  MAX_EXPLANATION_LENGTH = 2000

  belongs_to :task
  belongs_to :task_version
  belongs_to :action_node, optional: true
  belongs_to :recorded_by, class_name: 'User'

  validates :reason, presence: true, inclusion: { in: REASON_CODES }
  validates :previous_review_date, :new_review_date, presence: true
  validate :new_date_after_previous

  validates :explanation,
            length: { maximum: MAX_EXPLANATION_LENGTH },
            allow_blank: true

  private

  def new_date_after_previous
    return if previous_review_date.blank? || new_review_date.blank?
    return if new_review_date > previous_review_date

    errors.add(:new_review_date, 'must be after previous review date')
  end
end
