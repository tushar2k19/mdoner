# frozen_string_literal: true

module Imports
  class DashboardHtmlController < ApplicationController
    before_action :require_editor!

    # POST /imports/dashboard_html/preview
    # multipart: file=<dashboard.html>
    def preview
      file = params[:file]
      unless file.respond_to?(:read)
        render json: { error: "file is required" }, status: :bad_request
        return
      end

      limit = params[:limit].present? ? params[:limit].to_i : nil
      html = file.read

      tasks = Import::DashboardHtmlParser.parse(html, limit: limit)
      render json: { tasks: enrich_preview_tasks(tasks) }
    rescue ArgumentError => e
      render json: { error: e.message }, status: :unprocessable_entity
    rescue StandardError => e
      Rails.logger.error("[imports/dashboard_html/preview] #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}")
      render json: { error: "Failed to parse HTML" }, status: :internal_server_error
    end

    # POST /imports/dashboard_html/approve
    # json: { task: { sn, sector_division, description, responsibility }, nodes: [...] }
    def approve
      payload_task = params.require(:task).permit(:sn, :sector_division, :description, :responsibility)
      nodes = params.require(:nodes)
      replace_existing_new_task_id = params[:replace_existing_new_task_id].presence
      unless nodes.is_a?(Array)
        render json: { error: "nodes must be an array" }, status: :unprocessable_entity
        return
      end

      created = create_task_with_nodes!(payload_task.to_h, nodes, replace_existing_new_task_id: replace_existing_new_task_id)
      render json: created
    rescue ActionController::ParameterMissing => e
      render json: { error: e.message }, status: :bad_request
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages }, status: :unprocessable_entity
    rescue StandardError => e
      Rails.logger.error("[imports/dashboard_html/approve] #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}")
      render json: { error: "Failed to import task" }, status: :internal_server_error
    end

    # GET /imports/dashboard_html/existing_candidates?sector_division=IFD
    # Meeting-mode only: find existing NewTask rows for the given sector.
    def existing_candidates
      sector = params[:sector_division].to_s.strip
      if sector.blank?
        render json: { error: "sector_division is required" }, status: :bad_request
        return
      end

      # Prefer the latest *published snapshot* for this sector (matches what users see on NewFinalDashboard),
      # falling back to the latest living NewTask row if nothing has been published yet.
      latest_version = NewDashboardVersion.order(published_at: :desc).first
      snapshot =
        if latest_version
          latest_version.new_dashboard_snapshot_tasks
                        .where(sector_division: sector)
                        .order(display_position: :asc)
                        .first
        end

      candidates =
        if snapshot
          [serialize_existing_snapshot_candidate(snapshot, latest_version)]
        else
          # For now, only offer the latest matching row as the "existing task".
          NewTask.where(sector_division: sector).order(created_at: :desc).limit(1).map { |t| serialize_existing_candidate(t) }
        end

      render json: {
        sector_division: sector,
        candidates: candidates
      }
    end

    # GET /imports/dashboard_html/existing_task/:id
    # Returns a NewTask with flattened nodes so the import UI can display it.
    def existing_task
      id = params[:id]
      source = params[:source].to_s
      if source == "snapshot"
        snap = NewDashboardSnapshotTask.includes(:new_dashboard_snapshot_action_nodes).find(id)
        render json: serialize_existing_snapshot_task(snap)
      else
        task = NewTask.includes(:new_action_nodes).find(id)
        render json: serialize_existing_task(task)
      end
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Not found" }, status: :not_found
    end

    # DELETE /imports/dashboard_html/existing_task/:id
    # Soft-delete the NewTask (and dependent nodes) so the import row can be re-added.
    def delete_existing_task
      id = params[:id]
      task = NewTask.find(id)
      task.destroy!
      render json: { success: true, deleted_task_id: task.id }
    rescue ActiveRecord::RecordNotFound
      render json: { error: "Not found" }, status: :not_found
    end

    private

    def require_editor!
      return if current_user&.role.to_s.downcase == "editor"

      render json: { error: "Forbidden" }, status: :forbidden
    end

    def create_task_with_nodes!(task_hash, nodes, replace_existing_new_task_id: nil)
      # Allow client to override based on their UI mode (e.g. localStorage toggle)
      # but fallback to global server-side config.
      is_meeting = if meeting_dashboard_param_present?
                     ActiveModel::Type::Boolean.new.cast(meeting_dashboard_param_value)
                   else
                     Rails.configuration.x.meeting_dashboard_enabled
                   end

      if is_meeting
        create_new_flow_task_with_nodes!(task_hash, nodes, replace_existing_new_task_id: replace_existing_new_task_id)
      else
        create_legacy_task_with_nodes!(task_hash, nodes)
      end
    end

    def create_legacy_task_with_nodes!(task_hash, nodes)
      task = nil
      version = nil

      Task.transaction do
        task = Task.create!(
          sector_division: task_hash["sector_division"],
          description: task_hash["description"],
          responsibility: task_hash["responsibility"],
          original_date: Date.current,
          review_date: Date.current,
          editor: current_user,
          status: :draft
        )

        version = TaskVersion.create!(
          task: task,
          editor: current_user,
          version_number: 1,
          status: :draft
        )

        id_map = {}
        nodes_sorted = nodes.sort_by { |n| [n["level"].to_i, n["position"].to_i] }
        nodes_sorted.each do |n|
          temp_id = n["id"]
          parent_temp = n["parent_id"]
          parent_real = parent_temp ? id_map[parent_temp] : nil

          content = Import::HtmlSanitizer.sanitize_html(n["content"]).to_s
          content = Import::HtmlTableToResizableTable.normalize_complex_tables_in_html(content) if content.include?('<table')
          node_type = n["node_type"].presence || "rich_text"

          created_node = version.all_action_nodes.create!(
            parent_id: parent_real,
            content: content,
            level: n["level"].to_i,
            list_style: n["list_style"].presence || "decimal",
            node_type: node_type,
            position: n["position"].to_i,
            review_date: nil,
            completed: false
          )

          id_map[temp_id] = created_node.id
        end

        task.update!(current_version: version)
        task.update_review_date_from_nodes
      end

      { success: true, task_id: task.id, task_version_id: version.id, meeting_dashboard: false }
    end

    def create_new_flow_task_with_nodes!(task_hash, nodes, replace_existing_new_task_id: nil)
      task = nil
      deleted_replaced_task_id = nil

      NewTask.transaction do
        if replace_existing_new_task_id.present?
          existing = NewTask.find(replace_existing_new_task_id)
          existing.destroy!
          deleted_replaced_task_id = existing.id
        end

        task = NewTask.create!(
          sector_division: task_hash["sector_division"],
          description: task_hash["description"],
          responsibility: task_hash["responsibility"],
          original_date: Date.current,
          review_date: Date.current,
          editor: current_user,
          status: :draft
        )

        id_map = {}
        nodes_sorted = nodes.sort_by { |n| [n["level"].to_i, n["position"].to_i] }
        nodes_sorted.each do |n|
          temp_id = n["id"]
          parent_temp = n["parent_id"]
          parent_real = parent_temp ? id_map[parent_temp] : nil

          content = Import::HtmlSanitizer.sanitize_html(n["content"]).to_s
          content = Import::HtmlTableToResizableTable.normalize_complex_tables_in_html(content) if content.include?('<table')
          node_type = n["node_type"].presence || "rich_text"

          created_node = task.new_action_nodes.create!(
            parent_id: parent_real,
            content: content,
            level: n["level"].to_i,
            list_style: n["list_style"].presence || "decimal",
            node_type: node_type,
            position: n["position"].to_i,
            review_date: nil,
            completed: false
          )

          id_map[temp_id] = created_node.id
        end

        task.update_review_date_from_nodes
      end

      {
        success: true,
        task_id: task.id,
        task_version_id: nil,
        meeting_dashboard: true,
        deleted_replaced_task_id: deleted_replaced_task_id
      }
    end

    def enrich_preview_tasks(tasks)
      return [] unless tasks.is_a?(Array)

      # For now we only gate meeting-dashboard (new flow) imports.
      # If the user is in meeting mode, disable import for sectors that already exist in NewTask
      # until we define the merge/update behavior.
      is_meeting = if meeting_dashboard_param_present?
                     ActiveModel::Type::Boolean.new.cast(meeting_dashboard_param_value)
                   else
                     Rails.configuration.x.meeting_dashboard_enabled
                   end
      return tasks unless is_meeting

      sectors = tasks.map { |t| t.is_a?(Hash) ? (t["sector_division"] || t[:sector_division]) : nil }
                    .compact
                    .map(&:to_s)
                    .map(&:strip)
                    .reject(&:blank?)
                    .uniq

      existing = if sectors.empty?
                   []
                 else
                   NewTask.where(sector_division: sectors).distinct.pluck(:sector_division)
                 end
      existing_set = existing.map(&:to_s).to_h { |s| [s, true] }

      tasks.map do |t|
        next t unless t.is_a?(Hash)

        sec = (t["sector_division"] || t[:sector_division]).to_s
        t.merge("exists_in_new_task" => !!existing_set[sec])
      end
    end

    def serialize_existing_candidate(task)
      {
        id: task.id,
        source: "task",
        sector_division: task.sector_division,
        description: task.description,
        responsibility: task.responsibility,
        review_date: task.review_date,
        created_at: task.created_at
      }
    end

    def serialize_existing_snapshot_candidate(snapshot_task, version)
      {
        id: snapshot_task.id,
        source: "snapshot",
        new_dashboard_version_id: version&.id,
        published_at: version&.published_at,
        sector_division: snapshot_task.sector_division,
        description: snapshot_task.description,
        responsibility: snapshot_task.responsibility,
        review_date: snapshot_task.review_date
      }
    end

    def serialize_existing_task(task)
      {
        task: {
          id: task.id,
          sector_division: task.sector_division,
          description: task.description,
          responsibility: task.responsibility,
          review_date: task.review_date,
          status: task.status,
          replace_existing_new_task_id: task.id
        },
        nodes: task.new_action_nodes.map do |n|
          {
            id: n.id,
            parent_id: n.parent_id,
            content: n.content,
            level: n.level,
            list_style: n.list_style,
            node_type: n.node_type,
            position: n.position,
            review_date: n.review_date
          }
        end
      }
    end

    def serialize_existing_snapshot_task(task)
      {
        task: {
          id: task.id,
          sector_division: task.sector_division,
          description: task.description,
          responsibility: task.responsibility,
          review_date: task.review_date,
          status: "published_snapshot",
          new_dashboard_version_id: task.new_dashboard_version_id,
          replace_existing_new_task_id: task.source_new_task_id
        },
        nodes: task.new_dashboard_snapshot_action_nodes.map do |n|
          {
            id: n.id,
            parent_id: n.parent_id,
            content: n.content,
            level: n.level,
            list_style: n.list_style,
            node_type: n.node_type,
            position: n.position,
            review_date: n.review_date
          }
        end
      }
    end

    # Some tests call private methods directly on controller instances without request/params.
    # Guard param access so import helpers remain callable in that context.
    def meeting_dashboard_param_present?
      params.respond_to?(:key?) && params.key?(:meeting_dashboard)
    rescue StandardError
      false
    end

    def meeting_dashboard_param_value
      params[:meeting_dashboard]
    rescue StandardError
      nil
    end
  end
end
