# frozen_string_literal: true

require "test_helper"

# Mirrors frontend/src/utils/reviewerDiffHint.js — `shouldSuppressNoisyReviewerHint`.
# When baseline has no node-level reviewer, current does, and content + review dates are
# unchanged, the diff UI must not show "Unassigned → X" (round-trip assign noise).
class ReviewerHintSuppressTest < ActiveSupport::TestCase
  def suppress?(pair, content_changed:, dates_differ:)
    return false unless pair[:old_node] && pair[:new_node]
    return false if content_changed
    return false if dates_differ
    old_id = pair[:old_node][:reviewer_id]
    new_id = pair[:new_node][:reviewer_id]
    old_id.nil? && !new_id.nil?
  end

  test "suppresses when baseline unassigned, current assigned, same content and dates" do
    pair = {
      old_node: { reviewer_id: nil, content: "<p>x</p>" },
      new_node: { reviewer_id: 5, content: "<p>x</p>" }
    }
    assert suppress?(pair, content_changed: false, dates_differ: false)
  end

  test "does not suppress when content changed" do
    pair = {
      old_node: { reviewer_id: nil, content: "<p>a</p>" },
      new_node: { reviewer_id: 5, content: "<p>b</p>" }
    }
    assert_not suppress?(pair, content_changed: true, dates_differ: false)
  end

  test "does not suppress when review dates differ" do
    pair = {
      old_node: { reviewer_id: nil },
      new_node: { reviewer_id: 5 }
    }
    assert_not suppress?(pair, content_changed: false, dates_differ: true)
  end

  test "does not suppress when both sides have reviewer ids (real reassignment)" do
    pair = {
      old_node: { reviewer_id: 3 },
      new_node: { reviewer_id: 5 }
    }
    assert_not suppress?(pair, content_changed: false, dates_differ: false)
  end
end
