# frozen_string_literal: true

require "test_helper"

# Exercises the same grouped count used by TaskController#review_cycle (per-review comment totals).
class ReviewHubCommentsCountQueryTest < ActiveSupport::TestCase
  test "groups comment counts by review_id" do
    data = build_task_with_node_hierarchy
    editor = data[:editor]
    reviewer = data[:reviewer]
    task = data[:task]
    version = task.current_version
    version.update!(status: "under_review")

    r_a = Review.create!(task_version: version, reviewer: reviewer, reviewer_type: "task_level", status: "pending")
    r_b = Review.create!(task_version: version, reviewer: editor, reviewer_type: "task_level", status: "pending")

    ta = CommentTrail.create!(review: r_a)
    tb = CommentTrail.create!(review: r_b)
    Comment.create!(comment_trail: ta, user: editor, content: "one", review_date: Time.current)
    Comment.create!(comment_trail: ta, user: editor, content: "two", review_date: Time.current)
    Comment.create!(comment_trail: tb, user: reviewer, content: "solo", review_date: Time.current)

    ids = [r_a.id, r_b.id]
    counts = Comment.joins(:comment_trail)
                    .where(comment_trails: { review_id: ids })
                    .group("comment_trails.review_id")
                    .count

    assert_equal 2, counts[r_a.id]
    assert_equal 1, counts[r_b.id]
    assert_equal 3, counts.values.sum, "KPI total comments = sum of per-review comment counts"
  end
end
