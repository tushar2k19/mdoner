# frozen_string_literal: true

module MeetingDashboard
  class Rescheduler
    def self.call!(actor:, from_meeting_date:, to_meeting_date:, new_dashboard_version_id: nil)
      new(
        actor: actor,
        from_meeting_date: from_meeting_date,
        to_meeting_date: to_meeting_date,
        new_dashboard_version_id: new_dashboard_version_id
      ).call!
    end

    def initialize(actor:, from_meeting_date:, to_meeting_date:, new_dashboard_version_id:)
      @actor = actor
      @from = parse_date(from_meeting_date)
      @to = parse_date(to_meeting_date)
      @version_id = new_dashboard_version_id
    end

    def call!
      raise ArgumentError, "from_meeting_date and to_meeting_date must differ" if @from == @to

      schedule_from = NewMeetingSchedule.find_by(meeting_date: @from)
      version = resolve_version(schedule_from)
      raise ArgumentError, "No published dashboard version to attach" unless version

      schedule_to = nil

      ActiveRecord::Base.transaction do
        schedule_from&.destroy!

        schedule_to = NewMeetingSchedule.find_by(meeting_date: @to)
        if schedule_to
          schedule_to.update!(
            current_new_dashboard_version: version,
            set_by_user: @actor,
            set_at: Time.current
          )
        else
          schedule_to = NewMeetingSchedule.create!(
            meeting_date: @to,
            current_new_dashboard_version: version,
            set_by_user: @actor,
            set_at: Time.current
          )
        end

        NewMeetingScheduleEvent.create!(
          event_type: "reschedule",
          from_meeting_date: @from,
          to_meeting_date: @to,
          new_dashboard_version: version,
          new_meeting_schedule: schedule_to,
          actor: @actor,
          payload: {
            from: @from.to_s,
            to: @to.to_s,
            new_dashboard_version_id: version.id
          }
        )
      end

      schedule_to
    end

    private

    def parse_date(raw)
      Date.parse(raw.to_s)
    end

    def resolve_version(schedule_from)
      if @version_id.present? && @version_id.to_i.positive?
        return NewDashboardVersion.find_by(id: @version_id.to_i)
      end

      schedule_from&.current_new_dashboard_version || NewDashboardVersion.order(published_at: :desc).first
    end
  end
end
