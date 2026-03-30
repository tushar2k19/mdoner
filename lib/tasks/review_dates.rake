# frozen_string_literal: true

namespace :review_dates do
  desc <<~DESC
    Refresh action_node review_date values that are before today (IST).
    Assigns each a random date in today..today+30 (inclusive window), with 2–3 nodes pinned to today when possible.
    Recomputes parent node dates per version, then Task#update_review_date_from_nodes on affected current versions.
    No ReviewDateExtensionEvent rows are created.

    DRY_RUN=1   — print plan only
    RAILS_ENV   — development / production as usual

    Examples:
      bundle exec rake review_dates:refresh_past
      DRY_RUN=1 bundle exec rake review_dates:refresh_past
      RAILS_ENV=production bundle exec rake review_dates:refresh_past
  DESC
  task refresh_past: :environment do
    BulkRefreshActionNodeReviewDates.run
  end
end
