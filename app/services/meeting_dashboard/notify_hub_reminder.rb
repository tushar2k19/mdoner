# frozen_string_literal: true

module MeetingDashboard
  class NotifyHubReminder
    COOLDOWN = 10.minutes

    class << self
      # Returns :ok, :cooldown, or :no_assignees
      def call!(version:, stable_node_id:, actor:)
        return :no_assignees if stable_node_id.blank?

        snap = NewDashboardSnapshotActionNode.find_by(
          new_dashboard_version_id: version.id,
          stable_node_id: stable_node_id.to_s
        )
        return :no_assignees unless snap

        user_ids = NewDashboardAssignment.where(
          new_dashboard_version_id: version.id,
          new_dashboard_snapshot_action_node_id: snap.id
        ).distinct.pluck(:user_id)

        return :no_assignees if user_ids.empty?

        rec = MeetingHubReminderCooldown.find_or_initialize_by(
          editor_id: actor.id,
          new_dashboard_version_id: version.id,
          stable_node_id: stable_node_id.to_s
        )
        if rec.persisted? && rec.sent_at > COOLDOWN.ago
          return :cooldown
        end

        label = SnapshotNodeLabel.build(snap)
        task = snap.new_dashboard_snapshot_task

        rec.sent_at = Time.current
        rec.save!

        body = "Inputs still PENDING on Node #{label}. Click to respond now."
        payload_base = {
          new_dashboard_version_id: version.id,
          stable_node_id: snap.stable_node_id.to_s,
          new_task_id: task&.source_new_task_id,
          actor_id: actor.id,
          node_label: label,
          sector_division: task&.sector_division&.to_s&.strip.presence
        }.compact

        user_ids.each do |uid|
          next if uid == actor.id

          user = User.find_by(id: uid)
          next unless user && meeting_participant?(user)

          MeetingPackNotificationDispatcher.deliver!(
            user_id: uid,
            kind: MeetingPackNotification::KIND_HUB_REMINDER_PENDING,
            body: body,
            payload: payload_base,
            dedupe_key: "hub_reminder:#{rec.id}:#{uid}",
            channels: %i[in_app email]
          )
        end

        :ok
      end

      private

      def meeting_participant?(user)
        %w[editor reviewer final_reviewer].include?(user.role.to_s)
      end
    end
  end
end
