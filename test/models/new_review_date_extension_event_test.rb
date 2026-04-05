# frozen_string_literal: true

require "test_helper"

class NewReviewDateExtensionEventTest < ActiveSupport::TestCase
  setup do
    @editor = build_user(role: :editor, first_name: "E", last_name: "One")
    @nt = NewTask.create!(
      sector_division: "S",
      description: "D",
      original_date: Time.current,
      review_date: Time.current,
      responsibility: "R",
      editor: @editor,
      status: :draft
    )
    @node = @nt.new_action_nodes.create!(
      content: "n",
      level: 1,
      list_style: "decimal",
      node_type: "point",
      position: 1,
      review_date: Time.zone.parse("2026-01-10")
    )
  end

  test "valid create" do
    e = NewReviewDateExtensionEvent.new(
      new_task: @nt,
      new_action_node: @node,
      stable_node_id: @node.stable_node_id,
      previous_review_date: Date.new(2026, 1, 10),
      new_review_date: Date.new(2026, 3, 1),
      reason: "weather",
      explanation: "rain",
      recorded_by: @editor
    )
    assert e.valid?
    assert e.save
  end

  test "rejects invalid reason" do
    e = NewReviewDateExtensionEvent.new(
      new_task: @nt,
      new_action_node: @node,
      stable_node_id: @node.stable_node_id,
      previous_review_date: Date.new(2026, 1, 10),
      new_review_date: Date.new(2026, 3, 1),
      reason: "nope",
      recorded_by: @editor
    )
    assert_not e.valid?
    assert_includes e.errors[:reason], "is not included in the list"
  end

  test "rejects new_review_date not after previous" do
    e = NewReviewDateExtensionEvent.new(
      new_task: @nt,
      new_action_node: @node,
      stable_node_id: @node.stable_node_id,
      previous_review_date: Date.new(2026, 3, 10),
      new_review_date: Date.new(2026, 3, 1),
      reason: "other",
      recorded_by: @editor
    )
    assert_not e.valid?
    assert_includes e.errors[:new_review_date], "must be after previous review date"
  end

  test "rejects explanation too long" do
    e = NewReviewDateExtensionEvent.new(
      new_task: @nt,
      new_action_node: @node,
      stable_node_id: @node.stable_node_id,
      previous_review_date: Date.new(2026, 1, 10),
      new_review_date: Date.new(2026, 3, 1),
      reason: "other",
      explanation: "x" * (ReviewDateExtensionCodes::MAX_EXPLANATION_LENGTH + 1),
      recorded_by: @editor
    )
    assert_not e.valid?
    assert e.errors[:explanation].present?
  end
end
