# frozen_string_literal: true

module MeetingDashboard
  # Replace `new_task_tags` to match an explicit id list (e.g. from a published snapshot).
  class SyncNewTaskTags
    def self.call!(new_task:, tag_ids:, created_by_id: nil)
      new(new_task: new_task, tag_ids: tag_ids, created_by_id: created_by_id).call!
    end

    def initialize(new_task:, tag_ids:, created_by_id:)
      @new_task = new_task
      @tag_ids = Array(tag_ids).map(&:to_i).uniq.reject(&:zero?)
      @created_by_id = created_by_id
    end

    def call!
      NewTaskTag.where(new_task_id: @new_task.id).delete_all
      @tag_ids.each do |tid|
        NewTaskTag.create!(new_task_id: @new_task.id, tag_id: tid, created_by_id: @created_by_id)
      end
      true
    end
  end
end
