# frozen_string_literal: true

class NewDashboardSnapshotTask < ApplicationRecord
  acts_as_paranoid

  belongs_to :new_dashboard_version
  belongs_to :source_new_task, class_name: "NewTask", optional: true
  belongs_to :editor, class_name: "User", optional: true
  belongs_to :reviewer, class_name: "User", optional: true
  has_many :new_dashboard_snapshot_action_nodes, dependent: :destroy, inverse_of: :new_dashboard_snapshot_task

  validates :sector_division, :description, :original_date, :responsibility, :review_date, presence: true

  def node_tree
    nodes = new_dashboard_snapshot_action_nodes.to_a
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
    nodes = new_dashboard_snapshot_action_nodes.to_a
    reviewers = nodes.filter_map(&:reviewer).map(&:full_name).uniq.sort
    reviewers.any? ? reviewers.join(", ") : nil
  end
end
