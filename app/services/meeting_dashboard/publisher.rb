# frozen_string_literal: true

module MeetingDashboard
  class Publisher
    def self.call!(user:, target_meeting_date:)
      new(user: user, target_meeting_date: target_meeting_date).call!
    end

    def initialize(user:, target_meeting_date:)
      @user = user
      @target_meeting_date = target_meeting_date.is_a?(Date) ? target_meeting_date : Date.parse(target_meeting_date.to_s)
    end

    def call!
      tasks = NewTask.includes(:new_action_nodes, :tags).order(:id).to_a
      raise ArgumentError, "No draft tasks to publish" if tasks.empty?

      version = nil
      ActiveRecord::Base.transaction do
        version = NewDashboardVersion.create!(
          target_meeting_date: @target_meeting_date,
          published_at: Time.current,
          published_by: @user
        )

        tasks.each_with_index do |task, display_position|
          st = version.new_dashboard_snapshot_tasks.create!(
            source_new_task_id: task.id,
            sector_division: task.sector_division,
            description: task.description,
            original_date: task.original_date,
            review_date: task.review_date,
            responsibility: task.responsibility,
            completed_at: task.completed_at,
            status: task.read_attribute(:status),
            editor_id: task.editor_id,
            reviewer_id: task.reviewer_id,
            display_position: display_position,
            published_tag_ids: task.tags.order(:id).pluck(:id)
          )

          id_map = {}
          nodes_sorted = task.new_action_nodes.to_a.sort_by { |n| [n.level, n.position, n.id] }
          nodes_sorted.each do |n|
            parent_snap_id = n.parent_id ? id_map[n.parent_id] : nil
            snap = version.new_dashboard_snapshot_action_nodes.create!(
              new_dashboard_snapshot_task_id: st.id,
              source_new_action_node_id: n.id,
              parent_id: parent_snap_id,
              content: n.content,
              review_date: n.review_date,
              level: n.level,
              list_style: n.list_style,
              completed: n.completed,
              position: n.position,
              node_type: n.node_type,
              reviewer_id: n.reviewer_id,
              stable_node_id: n.stable_node_id
            )
            id_map[n.id] = snap.id
          end
        end

        schedule = NewMeetingSchedule.where(meeting_date: @target_meeting_date).order(id: :desc).first
        if schedule
          schedule.update!(
            current_new_dashboard_version: version,
            set_by_user: @user,
            set_at: Time.current
          )
        else
          schedule = NewMeetingSchedule.create!(
            meeting_date: @target_meeting_date,
            current_new_dashboard_version: version,
            set_by_user: @user,
            set_at: Time.current
          )
        end

        NewMeetingScheduleEvent.create!(
          event_type: "publish",
          new_dashboard_version: version,
          new_meeting_schedule: schedule,
          actor: @user,
          payload: { meeting_date: @target_meeting_date.to_s, version_id: version.id }
        )
      end

      version
    end
  end
end
