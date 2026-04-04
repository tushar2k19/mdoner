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
      render json: { tasks: tasks }
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
      unless nodes.is_a?(Array)
        render json: { error: "nodes must be an array" }, status: :unprocessable_entity
        return
      end

      created = create_task_with_nodes!(payload_task.to_h, nodes)
      render json: created
    rescue ActionController::ParameterMissing => e
      render json: { error: e.message }, status: :bad_request
    rescue ActiveRecord::RecordInvalid => e
      render json: { error: e.record.errors.full_messages }, status: :unprocessable_entity
    rescue StandardError => e
      Rails.logger.error("[imports/dashboard_html/approve] #{e.class}: #{e.message}\n#{e.backtrace.join("\n")}")
      render json: { error: "Failed to import task" }, status: :internal_server_error
    end

    private

    def require_editor!
      return if current_user&.role.to_s.downcase == "editor"

      render json: { error: "Forbidden" }, status: :forbidden
    end

    def create_task_with_nodes!(task_hash, nodes)
      if Rails.configuration.x.meeting_dashboard_enabled
        create_new_flow_task_with_nodes!(task_hash, nodes)
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

    def create_new_flow_task_with_nodes!(task_hash, nodes)
      task = nil

      NewTask.transaction do
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

      { success: true, task_id: task.id, task_version_id: nil, meeting_dashboard: true }
    end
  end
end
