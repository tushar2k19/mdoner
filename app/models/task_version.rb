# app/models/task_version.rb
class TaskVersion < ApplicationRecord
  belongs_to :task
  belongs_to :editor, class_name: 'User'
  belongs_to :base_version, class_name: 'TaskVersion', optional: true
  # has_many :action_nodes, dependent: :destroy
  has_many :action_nodes, -> { where(parent_id: nil) }, dependent: :destroy
  has_many :all_action_nodes, class_name: 'ActionNode', dependent: :destroy
  has_many :reviews, dependent: :destroy

  enum status: {
    draft: 'draft',
    under_review: 'under_review',
    approved: 'approved',
    completed: 'completed'
  }
  def create_new_draft(editor)
    new_version = task.versions.create!(
      editor: editor,
      base_version: self,
      version_number: task.versions.count + 1,
      status: :draft
    )

    # Deep copy action nodes with proper tree structure
    copy_action_nodes_to_version(new_version)
    new_version
  end

  # ActionNode Management Methods

  # Add a new node to this version
  def add_action_node(content:, level: 1, list_style: 'decimal', node_type: 'point', parent: nil, review_date: nil, completed: false)
    position = calculate_next_position(parent)
    
    all_action_nodes.create!(
      content: content,
      level: level,
      list_style: list_style,
      node_type: node_type,
      parent: parent,
      position: position,
      review_date: review_date,
      completed: completed
    )
  end

  # Add subpoint to an existing node
  def add_subpoint_to_node(parent_node, content:, list_style: nil, review_date: nil, completed: false)
    # Inherit or default list style based on level
    style = list_style || determine_list_style_for_level(parent_node.level + 1)
    
    add_action_node(
      content: content,
      level: parent_node.level + 1,
      list_style: style,
      node_type: 'subpoint',
      parent: parent_node,
      review_date: review_date,
      completed: completed
    )
  end

  # Get the complete node tree structure
  def node_tree
    root_nodes = action_nodes.order(:position)
    build_tree_structure(root_nodes)
  end

  # Get all nodes sorted by review date
  def nodes_by_review_date
    all_action_nodes.by_review_date
  end

  # Get nodes at specific level
  def nodes_at_level(level)
    all_action_nodes.at_level(level)
  end

  # Bulk update review dates and re-sort
  def update_and_resort_nodes
    # Only update task's review_date based on nearest node dates - no sorting
    task.update_review_date_from_nodes
  end

  # Check if this version has any content differences from base version
  def has_content_changes?
    return true unless base_version
    
    # Compare node content without position (since we removed sorting)
    current_nodes = all_action_nodes.pluck(:content, :level, :list_style, :review_date).sort
    base_nodes = base_version.all_action_nodes.pluck(:content, :level, :list_style, :review_date).sort
    
    current_nodes != base_nodes
  end

  # Get formatted content for display/export
  def formatted_content
    format_tree_nodes(node_tree).join("\n")
  end

  # Get HTML formatted content for dashboard display  
  def html_formatted_content
    format_html_tree_nodes(node_tree).join("")
  end

  # Gets all reviewers involved (for notifications)
  def all_reviewers
    reviews.map(&:reviewer).uniq
  end

  # Generate diff between this version and another version
  def diff_with(other_version)
    return {} unless other_version
    
    current_nodes = all_action_nodes.includes(:parent).to_a
    other_nodes = other_version.all_action_nodes.includes(:parent).to_a
    
    {
      added_nodes: find_added_nodes(current_nodes, other_nodes),
      removed_nodes: find_removed_nodes(current_nodes, other_nodes),
      modified_nodes: find_modified_nodes(current_nodes, other_nodes)
    }
  end

  # Check if this version's base is outdated compared to current approved
  def base_outdated?(current_approved_version)
    return false unless base_version && current_approved_version
    base_version.id != current_approved_version.id
  end

  # Merge nodes from another version into this version
  def merge_nodes_from(source_version, selected_node_ids = [])
    return false unless source_version
    
    ActiveRecord::Base.transaction do
      # If specific nodes selected, only merge those
      if selected_node_ids.any?
        nodes_to_merge = source_version.all_action_nodes.where(id: selected_node_ids)
      else
        # Merge all nodes from source
        nodes_to_merge = source_version.all_action_nodes
      end
      
      # Copy selected nodes maintaining tree structure
      node_mapping = {}
      root_nodes = nodes_to_merge.where(parent_id: nil).order(:position)
      
      root_nodes.each do |root_node|
        copy_node_tree(root_node, self, nil, node_mapping) if should_merge_node?(root_node)
      end
      
      # Update positions and resort
      update_and_resort_nodes
      true
    end
  rescue StandardError => e
    Rails.logger.error "Merge failed: #{e.message}"
    false
  end

  private

  def format_tree_nodes(tree_nodes)
    formatted_lines = []
    tree_nodes.each do |tree_item|
      formatted_lines << tree_item[:node].formatted_display
      if tree_item[:children].any?
        formatted_lines.concat(format_tree_nodes(tree_item[:children]))
      end
    end
    formatted_lines
  end

  def format_html_tree_nodes(tree_nodes)
    formatted_html = []
    tree_nodes.each do |tree_item|
      # Generate the current node's HTML
      node_html = tree_item[:node].html_formatted_display
      
      # If this node has children, we need to include them in a hierarchical structure
      if tree_item[:children].any?
        # For nodes with children, we maintain the flat structure but ensure proper ordering
        # The CSS handles indentation via level classes
        formatted_html << node_html
        formatted_html.concat(format_html_tree_nodes(tree_item[:children]))
      else
        # Leaf nodes are added as-is
        formatted_html << node_html
      end
    end
    formatted_html
  end

  # Deep copy action nodes maintaining tree structure
  def copy_action_nodes_to_version(target_version)
    node_mapping = {}
    
    # Copy root nodes first
    action_nodes.order(:position).each do |root_node|
      copy_node_tree(root_node, target_version, nil, node_mapping)
    end
  end

  # Recursively copy node and its children
  def copy_node_tree(source_node, target_version, new_parent, node_mapping)
    new_node = target_version.all_action_nodes.create!(
      content: source_node.content,
      level: source_node.level,
      list_style: source_node.list_style,
      node_type: source_node.node_type,
      position: source_node.position,
      review_date: source_node.review_date,
      completed: source_node.completed,
      parent: new_parent
    )
    
    node_mapping[source_node.id] = new_node.id
    
    # Copy children recursively
    source_node.children.order(:position).each do |child|
      copy_node_tree(child, target_version, new_node, node_mapping)
    end
    
    new_node
  end

  # Calculate next position for a node
  def calculate_next_position(parent)
    if parent
      parent.children.maximum(:position).to_i + 1
    else
      action_nodes.maximum(:position).to_i + 1
    end
  end

  # Determine appropriate list style based on level
  def determine_list_style_for_level(level)
    case level
    when 1
      'decimal'      # 1, 2, 3...
    when 2
      'lower-alpha'  # a, b, c...
    when 3
      'lower-roman'  # i, ii, iii...
    else
      'bullet'       # • for deeper levels
    end
  end

  # Build hierarchical tree structure from flat nodes
  def build_tree_structure(nodes)
    nodes.map do |node|
      {
        node: node,
        children: build_tree_structure(node.children.order(:position))
      }
    end
  end

  # Helper methods for diff comparison
  def find_added_nodes(current_nodes, other_nodes)
    current_nodes.reject do |current_node|
      other_nodes.any? { |other_node| nodes_equivalent?(current_node, other_node) }
    end
  end

  def find_removed_nodes(current_nodes, other_nodes)
    other_nodes.reject do |other_node|
      current_nodes.any? { |current_node| nodes_equivalent?(current_node, other_node) }
    end
  end

  def find_modified_nodes(current_nodes, other_nodes)
    modified = []
    current_nodes.each do |current_node|
      # Find equivalent node in other version by content and structure
      other_node = other_nodes.find { |n| nodes_structurally_equivalent?(current_node, n) }
      if other_node && !nodes_content_equal?(current_node, other_node)
        modified << current_node
      end
    end
    modified
  end

  def nodes_equivalent?(node1, node2)
    # Compare content and structure, but not position (which can change)
    node1.content.strip == node2.content.strip &&
    node1.level == node2.level &&
    node1.list_style == node2.list_style
  end

  def nodes_structurally_equivalent?(node1, node2)
    # Check if nodes represent the same logical content
    node1.content.strip == node2.content.strip &&
    node1.level == node2.level &&
    node1.list_style == node2.list_style
  end

  def nodes_content_equal?(node1, node2)
    node1.content.strip == node2.content.strip &&
    node1.review_date == node2.review_date &&
    node1.completed == node2.completed
  end

  def should_merge_node?(node)
    # Check if node already exists in current version
    !all_action_nodes.exists?(
      content: node.content,
      level: node.level,
      list_style: node.list_style
    )
  end
end
