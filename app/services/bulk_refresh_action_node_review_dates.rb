# frozen_string_literal: true

# One-off / periodic maintenance: shift stale action_node.review_date values into a forward window.
# Uses IST (same as Task#update_review_date_from_nodes) for "today".
# Does not create ReviewDateExtensionEvent rows — uses update_all / update_column only.
class BulkRefreshActionNodeReviewDates
  IST = 'Asia/Kolkata'
  WINDOW_DAYS = 30

  def self.run(**kwargs)
    new(**kwargs).run
  end

  # @param dry_run [Boolean] if true, only report what would change
  # @param io [IO] stdout/stderr for messages
  # @param random [Random] inject for tests
  def initialize(dry_run: ENV['DRY_RUN'].to_s.strip.in?(%w[1 true yes]), io: $stdout, random: nil)
    @dry_run = dry_run
    @io = io
    @random = random || Random.new
  end

  def run
    zone = Time.find_zone!(IST)
    today_date = Time.current.in_time_zone(zone).to_date
    start_today = zone.local(today_date.year, today_date.month, today_date.day).beginning_of_day

    node_ids = ActionNode
               .where.not(review_date: nil)
               .where('review_date < ?', start_today)
               .pluck(:id)

    if node_ids.empty?
      @io.puts '[bulk_refresh_review_dates] No action nodes with review_date before today (IST). Nothing to do.'
      return summary_result(0, 0, [], today_date)
    end

    shuffled = node_ids.shuffle(random: @random)
    pin_n = pin_today_count(shuffled.size)
    pinned = shuffled.take(pin_n)
    rest = shuffled.drop(pin_n)

    assignments = {}
    pinned.each { |id| assignments[id] = midday_ist(zone, today_date) }
    rest.each do |id|
      offset = @random.rand(0..WINDOW_DAYS)
      assignments[id] = midday_ist(zone, today_date + offset.days)
    end

    affected_version_ids = ActionNode.unscoped.where(id: assignments.keys).distinct.pluck(:task_version_id).sort

    if @dry_run
      print_dry_run(assignments, today_date, pin_n, affected_version_ids)
      return summary_result(assignments.size, pin_n, affected_version_ids, today_date)
    end

    ApplicationRecord.transaction do
      assignments.each do |id, time|
        ActionNode.where(id: id).update_all(review_date: time, updated_at: Time.current)
      end

      affected_version_ids.each { |vid| refresh_aggregated_parent_dates!(vid) }

      task_ids = Task.where(current_version_id: affected_version_ids).pluck(:id)
      Task.where(id: task_ids).find_each(&:update_review_date_from_nodes)
    end

    @io.puts "[bulk_refresh_review_dates] Updated #{assignments.size} nodes (IST today=#{today_date}; " \
             "#{pin_n} pinned to today). Refreshed parents for #{affected_version_ids.size} task version(s). " \
             "Synced #{Task.where(current_version_id: affected_version_ids).count} task(s) from nodes."
    summary_result(assignments.size, pin_n, affected_version_ids, today_date)
  end

  private

  def pin_today_count(n)
    return 0 if n <= 0
    return 1 if n == 1
    return 2 if n == 2

    3
  end

  def midday_ist(zone, date)
    zone.local(date.year, date.month, date.day, 12, 0, 0)
  end

  # After leaf dates change, recompute parent action_node.review_date as min(children) up the tree.
  def refresh_aggregated_parent_dates!(task_version_id)
    ActionNode.unscoped
              .where(task_version_id: task_version_id)
              .order(level: :desc, position: :asc)
              .find_each do |node|
      child_ids = ActionNode.unscoped.where(parent_id: node.id).pluck(:id)
      next if child_ids.empty?

      earliest = ActionNode.unscoped.where(id: child_ids).where.not(review_date: nil).minimum(:review_date)
      next unless earliest

      ActionNode.unscoped.where(id: node.id).update_all(review_date: earliest, updated_at: Time.current)
    end
  end

  def print_dry_run(assignments, today_date, pin_n, version_ids)
    @io.puts '[bulk_refresh_review_dates] DRY RUN — no writes.'
    @io.puts "  IST today: #{today_date}"
    @io.puts "  Nodes to update: #{assignments.size}"
    @io.puts "  Pinned to today: #{pin_n}"
    @io.puts "  Affected task_version ids: #{version_ids.join(', ')}"
    sample = assignments.first(5).map { |id, t| "id=#{id} -> #{t.to_date}" }
    @io.puts "  Sample: #{sample.join('; ')}"
  end

  def summary_result(updated, pinned_to_today, version_ids, today_date)
    {
      updated_count: updated,
      pinned_to_today: pinned_to_today,
      affected_task_version_ids: version_ids,
      ist_today: today_date,
      dry_run: @dry_run
    }
  end
end
