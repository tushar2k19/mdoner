# frozen_string_literal: true

module MeetingDashboard
  class NotifyPackAssignment
    class << self
      def call!(version:, snap:, assignment:, assignee:, actor:)
        return if assignee.blank? || assignee.id == actor&.id
        return unless meeting_participant?(assignee)

        label = SnapshotNodeLabel.build(snap)
        task = snap.new_dashboard_snapshot_task
        body = "Editor needs inputs from you on Node #{label}. Click to respond now."
        payload = base_payload(version, snap, task, actor).merge("node_label" => label)

        MeetingPackNotificationDispatcher.deliver!(
          user_id: assignee.id,
          kind: MeetingPackNotification::KIND_PACK_ASSIGNMENT_CREATED,
          body: body,
          payload: payload,
          dedupe_key: "pack_assignment_created:#{assignment.id}",
          channels: %i[in_app email]
        )
      end

      private

      def meeting_participant?(user)
        %w[editor reviewer final_reviewer].include?(user.role.to_s)
      end

      def base_payload(version, snap, task, actor)
        {
          new_dashboard_version_id: version.id,
          stable_node_id: snap.stable_node_id.to_s,
          new_task_id: task&.source_new_task_id,
          actor_id: actor&.id,
          sector_division: task&.sector_division&.to_s&.strip.presence
        }.compact
      end
    end
  end
end
