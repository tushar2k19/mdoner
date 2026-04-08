# frozen_string_literal: true

module MeetingDashboard
  class NotifyDashboardNodeComment
    class << self
      def call!(version:, snap:, actor:)
        label = SnapshotNodeLabel.build(snap)
        task = snap.new_dashboard_snapshot_task

        if actor.editor?
          notify_assignees_r2(version, snap, task, actor, label)
        elsif actor.reviewer? || actor.final_reviewer?
          notify_editor_e1(version, snap, task, actor, label)
        end
      end

      private

      def meeting_participant?(user)
        user && %w[editor reviewer final_reviewer].include?(user.role.to_s)
      end

      def notify_assignees_r2(version, snap, task, actor, label)
        user_ids = NewDashboardAssignment.where(
          new_dashboard_version_id: version.id,
          new_dashboard_snapshot_action_node_id: snap.id
        ).distinct.pluck(:user_id)

        user_ids.each do |uid|
          next if uid == actor.id

          user = User.find_by(id: uid)
          next unless meeting_participant?(user)

          body = "New comments added on Node #{label}. Check now!!"
          MeetingPackNotificationDispatcher.deliver!(
            user_id: uid,
            kind: MeetingPackNotification::KIND_DASHBOARD_NODE_COMMENT_FOR_ASSIGNEES,
            body: body,
            payload: base_payload(version, snap, task, actor).merge("node_label" => label),
            dedupe_key: "node_comment_burst:#{version.id}:#{snap.stable_node_id}:#{uid}:#{comment_bucket_key}",
            channels: %i[in_app email]
          )
        end
      end

      def notify_editor_e1(version, snap, task, actor, label)
        editor_id = task&.editor_id
        return if editor_id.blank? || editor_id == actor.id

        editor = User.find_by(id: editor_id)
        return unless meeting_participant?(editor)

        body = "New comments added on Node #{label}. Check now!!"
        MeetingPackNotificationDispatcher.deliver!(
          user_id: editor_id,
          kind: MeetingPackNotification::KIND_DASHBOARD_NODE_COMMENT_FOR_EDITORS,
          body: body,
          payload: base_payload(version, snap, task, actor).merge("node_label" => label)
        )
      end

      def base_payload(version, snap, task, actor)
        {
          new_dashboard_version_id: version.id,
          stable_node_id: snap.stable_node_id.to_s,
          new_task_id: task&.source_new_task_id,
          actor_id: actor.id,
          sector_division: task&.sector_division&.to_s&.strip.presence
        }.compact
      end

      def comment_bucket_key
        now = Time.current.utc
        bucket_minute = (now.min / 10) * 10
        now.change(min: bucket_minute, sec: 0).strftime("%Y%m%d%H%M")
      end
    end
  end
end
