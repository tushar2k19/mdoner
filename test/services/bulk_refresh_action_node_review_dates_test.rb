# frozen_string_literal: true

require 'test_helper'

class BulkRefreshActionNodeReviewDatesTest < ActiveSupport::TestCase
  # time travel + ordering; avoid flaky parallel run
  parallelize(workers: 1)

  setup do
    @zone = Time.find_zone!(BulkRefreshActionNodeReviewDates::IST)
  end

  test 'moves past node dates into today..today+30 IST and syncs task' do
    zone = @zone
    travel_to zone.local(2026, 3, 30, 12, 0, 0) do
      ctx = build_task_with_node_hierarchy
      task = ctx[:task]
      version = ctx[:version]

      past = zone.local(2026, 2, 12, 8, 0, 0)
      version.all_action_nodes.find_each { |n| n.update_column(:review_date, past) }
      task.update_column(:review_date, past.to_date)

      rng = Random.new(42)
      io = StringIO.new
      result = BulkRefreshActionNodeReviewDates.new(dry_run: false, io: io, random: rng).run

      assert result[:updated_count] >= 1

      version.all_action_nodes.reload.find_each do |node|
        assert node.review_date.present?
        nd = node.review_date.in_time_zone(zone).to_date
        assert nd >= Date.new(2026, 3, 30), "node #{node.id} should be on/after 2026-03-30, was #{nd}"
        assert nd <= Date.new(2026, 4, 29), "node #{node.id} should be within 30d window, was #{nd}"
      end

      today_count = version.all_action_nodes.reload.count do |n|
        n.review_date.in_time_zone(zone).to_date == Date.new(2026, 3, 30)
      end
      assert today_count >= 2, "expected at least 2 nodes on today, got #{today_count}"

      task.reload
      task_d = task.review_date.respond_to?(:to_date) ? task.review_date.to_date : task.review_date
      assert_operator task_d, :>=, Date.new(2026, 3, 30)
    end
  end

  test 'dry run does not change database' do
    zone = @zone
    travel_to zone.local(2026, 3, 30, 12, 0, 0) do
      ctx = build_task_with_node_hierarchy
      version = ctx[:version]

      past = zone.local(2026, 2, 12, 8, 0, 0)
      version.all_action_nodes.find_each { |n| n.update_column(:review_date, past) }

      before = version.all_action_nodes.pluck(:id, :review_date).to_h

      BulkRefreshActionNodeReviewDates.new(dry_run: true, io: StringIO.new, random: Random.new(1)).run

      after = version.all_action_nodes.reload.pluck(:id, :review_date).to_h
      assert_equal before, after
    end
  end
end
