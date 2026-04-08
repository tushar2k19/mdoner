# frozen_string_literal: true

class MeetingDashboard::TasksController < ApplicationController
  include MeetingDashboardSerialization

  before_action :set_task, only: [:update, :destroy, :nodes]

  def nodes
    tree = @task.node_tree
    calculate_display_counters(tree)
    render json: { success: true, data: serialize_flat_with_counters(tree) }
  end

  def create
    task = NewTask.new(task_params)
    task.editor = current_user

    if task.save
      apply_tag_ids_to_new_task!(task, tag_ids_from_request) if tag_ids_key_present?
      if params[:action_nodes].present?
        sync_nodes(task, params[:action_nodes])
      end
      update_review_date_from_nodes(task)
      render json: { success: true, data: serialize_meeting_new_task(task.reload) }
    else
      render json: { success: false, error: task.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def update
    if @task.update(task_params)
      apply_tag_ids_to_new_task!(@task, tag_ids_from_request) if tag_ids_key_present?
      if params[:action_nodes].present?
        sync_nodes(@task, params[:action_nodes])
      end
      update_review_date_from_nodes(@task)
      render json: { success: true, data: serialize_meeting_new_task(@task.reload) }
    else
      render json: { success: false, error: @task.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @task.destroy
    render json: { success: true }
  end

  private

  def set_task
    @task = NewTask.find(params[:id])
  end

  def task_params
    params.require(:task).permit(:sector_division, :description, :responsibility, :original_date, :review_date, :status)
  end

  def update_review_date_from_nodes(task)
    latest_date = task.new_action_nodes.maximum(:review_date)
    task.update_column(:review_date, latest_date) if latest_date
  end

  def sync_nodes(task, nodes_data)
    flat_nodes = flatten_node_structure(nodes_data)
    
    existing_nodes = task.new_action_nodes.to_a
    existing_by_stable = existing_nodes.index_by(&:stable_node_id)
    
    temp_to_created = {}
    seen_ids = []
    
    flat_nodes.each_with_index do |node_data, index|
      stable_id = node_data['stable_node_id']
      node = if stable_id.present? && existing_by_stable[stable_id]
               existing_by_stable[stable_id]
             else
               task.new_action_nodes.build
             end
      
      parent_id = nil
      if node_data['parent_id']
        if node_data['parent_id'].to_i < 0 && temp_to_created[node_data['parent_id'].to_i]
          parent_id = temp_to_created[node_data['parent_id'].to_i]
        else
          parent_id = node_data['parent_id']
        end
      end
      
      node.assign_attributes(
        content: normalize_complex_table_content(node_data['content']),
        level: node_data['level'] || 1,
        list_style: node_data['list_style'] || 'decimal',
        node_type: node_data['node_type'] || 'point',
        parent_id: parent_id,
        position: index + 1,
        review_date: node_data['review_date'],
        completed: node_data['completed'] || false,
        reviewer_id: node_data['reviewer_id']
      )
      
      node.save!
      
      if node_data['id'] && node_data['id'].to_i < 0
        temp_to_created[node_data['id'].to_i] = node.id
      end
      seen_ids << node.id
    end
    
    existing_nodes.each do |n|
      n.destroy unless seen_ids.include?(n.id)
    end
  end

  def tag_ids_key_present?
    params[:task].is_a?(ActionController::Parameters) && params[:task].key?(:tag_ids)
  end

  def tag_ids_from_request
    raw = params.dig(:task, :tag_ids)
    raw.is_a?(Array) ? raw : []
  end

  # Same semantics as TaskController#apply_tags! — shared Tag rows, join on new_task_tags.
  def apply_tag_ids_to_new_task!(new_task, tag_ids)
    tag_ids = tag_ids.map(&:to_i).uniq.reject(&:zero?)
    existing_ids = new_task.tags.pluck(:id)
    to_add = tag_ids - existing_ids
    to_remove = existing_ids - tag_ids
    NewTaskTag.where(new_task_id: new_task.id, tag_id: to_remove).delete_all if to_remove.any?
    to_add.each do |tid|
      NewTaskTag.create!(new_task_id: new_task.id, tag_id: tid, created_by_id: current_user.id)
    end
  end

  def flatten_node_structure(nodes_data)
    return [] if nodes_data.blank?
    return nodes_data unless nodes_data.first&.key?('children') || nodes_data.first&.key?('node')
    
    flat_nodes = []
    nodes_data.each do |node_item|
      if node_item.key?('node')
        flat_nodes << node_item['node']
        flat_nodes.concat(flatten_node_structure(node_item['children'])) if node_item['children']&.any?
      elsif node_item.key?('content')
        node_copy = node_item.except('children')
        flat_nodes << node_copy
        flat_nodes.concat(flatten_node_structure(node_item['children'])) if node_item['children']&.any?
      else
        flat_nodes << node_item
      end
    end
    flat_nodes
  end

  def normalize_complex_table_content(content)
    raw = content.to_s
    return raw unless raw.include?('<table')

    Import::HtmlTableToResizableTable.normalize_complex_tables_in_html(raw)
  end
end