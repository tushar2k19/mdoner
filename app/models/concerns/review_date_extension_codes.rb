# frozen_string_literal: true

# Shared reason vocabulary and limits for legacy ReviewDateExtensionEvent and
# meeting-dashboard NewReviewDateExtensionEvent.
module ReviewDateExtensionCodes
  REASON_CODES = %w[
    operational
    financial
    weather
    misc
    technical
    other
  ].freeze

  MAX_EXPLANATION_LENGTH = 2000
end
