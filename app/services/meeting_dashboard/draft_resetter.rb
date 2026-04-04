# frozen_string_literal: true

module MeetingDashboard
  class DraftResetter
    def self.call!(user:)
      new(user: user).call!
    end

    def initialize(user:)
      @user = user
    end

    def call!
      latest = NewDashboardVersion.order(published_at: :desc).first
      raise ArgumentError, "No published dashboard to reset from" unless latest

      snapshot_tasks = latest.new_dashboard_snapshot_tasks.order(:display_position).includes(:new_dashboard_snapshot_action_nodes).to_a
      raise ArgumentError, "Latest published version has no snapshot tasks" if snapshot_tasks.empty?

      ActiveRecord::Base.transaction do
        source_ids = snapshot_tasks.map(&:source_new_task_id).compact.to_set

        snapshot_tasks.each do |st|
          living = if st.source_new_task_id.present? && NewTask.exists?(id: st.source_new_task_id)
                     NewTask.find(st.source_new_task_id)
                   else
                     NewTask.create!(
                       sector_division: st.sector_division,
                       description: st.description,
                       original_date: st.original_date,
                       review_date: st.review_date,
                       responsibility: st.responsibility,
                       editor_id: st.editor_id || @user.id,
                       reviewer_id: st.reviewer_id,
                       status: st.read_attribute(:status),
                       completed_at: st.completed_at
                     )
                   end

          living.update!(
            sector_division: st.sector_division,
            description: st.description,
            original_date: st.original_date,
            review_date: st.review_date,
            responsibility: st.responsibility,
            editor_id: st.editor_id || living.editor_id || @user.id,
            reviewer_id: st.reviewer_id,
            status: st.read_attribute(:status),
            completed_at: st.completed_at
          )

          # Tags are draft-only until publish; snapshot stores the published set so reset can drop
          # tags added after the last Submit (see published_tag_ids on snapshot tasks).
          tag_ids = st.read_attribute(:published_tag_ids)
          unless tag_ids.nil?
            MeetingDashboard::SyncNewTaskTags.call!(
              new_task: living,
              tag_ids: tag_ids,
              created_by_id: st.editor_id || @user.id
            )
          end

          destroy_nodes_bottom_up(living)

          id_map = {}
          nodes_sorted = st.new_dashboard_snapshot_action_nodes.to_a.sort_by { |n| [n.level, n.position, n.id] }
          nodes_sorted.each do |snap|
            parent_living = snap.parent_id ? id_map[snap.parent_id] : nil
            node = living.new_action_nodes.create!(
              parent_id: parent_living,
              content: snap.content,
              review_date: snap.review_date,
              level: snap.level,
              list_style: snap.list_style,
              completed: snap.completed,
              position: snap.position,
              node_type: snap.node_type,
              reviewer_id: snap.reviewer_id,
              stable_node_id: snap.stable_node_id
            )
            id_map[snap.id] = node.id
          end
        end

        if source_ids.any?
          NewTask.where.not(id: source_ids.to_a).find_each(&:destroy)
        end
      end

      true
    end

    private

    def destroy_nodes_bottom_up(task)
      NewActionNode.unscoped.where(new_task_id: task.id).order(level: :desc).find_each do |node|
        node.really_destroy!
      end
    end
  end
end
