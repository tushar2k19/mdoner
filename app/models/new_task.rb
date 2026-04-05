# frozen_string_literal: true

class NewTask < ApplicationRecord
  acts_as_paranoid

  belongs_to :editor, class_name: "User", optional: true
  belongs_to :reviewer, class_name: "User", optional: true
  has_many :new_action_nodes, dependent: :destroy, inverse_of: :new_task
  has_many :new_review_date_extension_events, dependent: :destroy
  has_many :new_task_tags, dependent: :destroy
  has_many :tags, through: :new_task_tags
  has_many :root_new_action_nodes, -> { where(parent_id: nil).order(:position) },
           class_name: "NewActionNode",
           inverse_of: :new_task,
           dependent: :destroy

  enum status: {
    draft: 0,
    under_review: 1,
    approved: 3,
    completed: 4
  }

  validates :sector_division, :description, :original_date, :responsibility, :review_date, presence: true

  # In-memory tree (no extra queries if new_action_nodes preloaded)
  def node_tree
    nodes = new_action_nodes.to_a
    build_tree_structure_in_memory(nodes)
  end

  def build_tree_structure_in_memory(nodes)
    nodes_by_parent = nodes.group_by(&:parent_id)
    build_subtree = lambda do |parent_id|
      child_nodes = nodes_by_parent[parent_id] || []
      child_nodes.sort_by(&:position).map do |node|
        { node: node, children: build_subtree.call(node.id) }
      end
    end
    build_subtree.call(nil)
  end

  def html_formatted_content(counters_map, tree = nil)
    tree ||= node_tree
    format_html_tree_nodes(tree, counters_map).join("")
  end

  def format_html_tree_nodes(tree_nodes, counters_map = nil)
    formatted_html = []
    tree_nodes.each do |tree_item|
      node = tree_item[:node]
      counter = counters_map ? counters_map[node.id] : node.display_counter
      node_html = node.html_formatted_display(counter)
      if tree_item[:children].any?
        formatted_html << node_html
        formatted_html.concat(format_html_tree_nodes(tree_item[:children], counters_map))
      else
        formatted_html << node_html
      end
    end
    formatted_html
  end

  def reviewer_info
    nodes = new_action_nodes.to_a
    reviewers = nodes.filter_map(&:reviewer).map(&:full_name).uniq.sort
    reviewers.any? ? reviewers.join(", ") : nil
  end

  def update_review_date_from_nodes
    return if new_action_nodes.empty?

    current_date_ist = Time.current.in_time_zone("Asia/Kolkata").to_date
    future_dates = new_action_nodes.where.not(review_date: nil)
                                    .where("review_date >= ?", current_date_ist)
                                    .pluck(:review_date)
    return if future_dates.empty?

    nearest_future_date = future_dates.min
    update_column(:review_date, nearest_future_date) if nearest_future_date != review_date
  end
end
