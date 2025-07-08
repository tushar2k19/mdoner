# app/models/action_node.rb
class ActionNode < ApplicationRecord
  belongs_to :task_version
  belongs_to :parent, class_name: 'ActionNode', optional: true
  has_many :children, class_name: 'ActionNode', foreign_key: 'parent_id', dependent: :destroy
  has_many :comments, dependent: :nullify

  validates :node_type, presence: true,
            inclusion: { in: %w[paragraph point subpoint subsubpoint table rich_text]  #add others if necessary
            }
  validates :list_style, presence: true,
            inclusion: { in: %w[decimal lower-alpha lower-roman bullet] }
  validates :level, presence: true, numericality: { greater_than: 0 }
  accepts_nested_attributes_for :children, allow_destroy: true


  validates :content, presence: true
  validates :position, presence: true
  before_validation :set_default_position, on: :create

  # Automatic sorting
  default_scope { order(position: :asc) }

  def copy_to_version(new_version, parent_mapping = {})
    new_parent = parent_mapping[parent_id]

    new_node = new_version.action_nodes.create!(
      parent: new_parent,
      content: content,
      review_date: review_date,
      completed: completed,
      node_type: node_type,
      position: position
    )

    # Store mapping for children
    parent_mapping[id] = new_node.id

    # Recursively copy children
    children.each do |child|
      child.copy_to_version(new_version, parent_mapping)
    end

    new_node
  end

  # Finds equivalent node in another version
  def find_in_version(target_version)
    return nil unless id

    # More reliable lookup using original ID tracking
    if target_version.task_id == task_version.task_id
      target_version.action_nodes.find_by(original_id: id)
    else
      # Fallback for cross-task comparisons
      target_version.action_nodes.find_by(
        content: content,
        node_type: node_type,
        position: position,
        parent_id: parent&.find_in_version(target_version)&.id
      )
    end
  end

  def update_completion_status
    if children.any?
      update(completed: children.all?(&:completed))
    end
    parent&.update_completion_status
  end

  # Propagate review dates upward
  def update_review_date
    if children.any?
      earliest_date = children.map(&:review_date).compact.min
      update(review_date: earliest_date) if earliest_date
    end
    parent&.update_review_date
  end

  # Level management methods
  def increment_level
    update(level: level + 1)
    children.each(&:increment_level)
  end

  def decrement_level
    return if level <= 1
    update(level: level - 1)
    children.each(&:decrement_level)
  end

  # Counter generation based on list style and position
  def display_counter
    # Get the counter position within nodes of the same list style at the same level
    # Count only siblings with the same list style that come before or at this position
    siblings_before_and_including_me = siblings_with_same_style.where('position <= ?', position).order(:position)
    counter_position = siblings_before_and_including_me.count
    
    case list_style
    when 'decimal'
      "#{counter_position}"
    when 'lower-alpha'
      (96 + counter_position).chr # a, b, c...
    when 'lower-roman'
      to_roman(counter_position).downcase
    when 'bullet'
      '•'
    else
      counter_position.to_s
    end
  end

  # Get formatted display with counter and indentation
  def formatted_display
    indent = '  ' * (level - 1)  # 2 spaces per level
    counter = display_counter
    
    # For rich text or table nodes, strip HTML for plain text display
    display_content = (node_type == 'rich_text' || node_type == 'table') ? strip_html_tags(content) : content
    
    case list_style
    when 'bullet'
      "#{indent}#{counter} #{display_content}"
    else
      "#{indent}#{counter}. #{display_content}"
    end
  end

  # Get HTML content for rich display
  def html_content
    case node_type
    when 'rich_text', 'table'
      content # Return HTML as-is
    else
      # Escape plain text content using CGI
      CGI.escapeHTML(content)
    end
  end

  # Get formatted HTML display with counter, indentation and styling for dashboard
  def html_formatted_display
    counter = display_counter
    content_html = html_content
    
    # Format review date if present
    review_date_html = ""
    if review_date.present?
      formatted_date = review_date.strftime("%d/%m") # Only day and month
      is_today = review_date.to_date == Date.current
      date_classes = ["review-date"]
      date_classes << "today" if is_today
      review_date_html = %( <span class="#{date_classes.join(' ')}">#{formatted_date}</span>)
    end
    
    # Generate CSS classes based on level and list style
    css_classes = ["action-node", "level-#{level}", "style-#{list_style}"]
    css_classes << "completed" if completed
    
    # Generate the HTML structure
    case list_style
    when 'bullet'
      %(<div class="#{css_classes.join(' ')}">
          <span class="node-marker">#{counter}</span>
          <span class="node-content">#{content_html}#{review_date_html}</span>
        </div>).html_safe
    else
      %(<div class="#{css_classes.join(' ')}">
          <span class="node-marker">#{counter}.</span>
          <span class="node-content">#{content_html}#{review_date_html}</span>
        </div>).html_safe
    end
  end

  # Check if node contains rich formatting
  def has_rich_formatting?
    node_type == 'rich_text' || node_type == 'table' || content.match?(/<[^>]+>/)
  end

  # Get all descendant nodes (recursive)
  def all_descendants
    children.flat_map { |child| [child] + child.all_descendants }
  end

  # Get nodes at specific level
  def self.at_level(level_num)
    where(level: level_num)
  end

  # Sort nodes by review date, with nil dates last
  def self.by_review_date
    order(Arel.sql('review_date IS NULL, review_date ASC'))
  end

  # Check if node can be moved to different level
  def can_change_level?(new_level)
    return false if new_level < 1
    return false if parent && new_level <= parent.level
    true
  end

  # Safe delete that handles children first
  def safe_destroy
    # Delete all descendants first (bottom-up)
    all_descendants.reverse.each(&:destroy!)
    # Then delete self
    destroy!
  end

  private

  def strip_html_tags(html_content)
    html_content.gsub(/<[^>]*>/, '').strip
  end

  def set_default_position
    self.position ||= siblings.maximum(:position).to_i + 1
  end

  def siblings
    parent ? parent.children : task_version.action_nodes.where(parent_id: nil)
  end

  def siblings_with_same_style
    parent ? parent.children.where(list_style: list_style) : task_version.action_nodes.where(parent_id: nil).where(list_style: list_style)
  end

  # Convert integer to Roman numeral
  def to_roman(number)
    return '' if number <= 0
    
    values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
    literals = ['M', 'CM', 'D', 'CD', 'C', 'XC', 'L', 'XL', 'X', 'IX', 'V', 'IV', 'I']
    
    roman = ''
    values.each_with_index do |value, index|
      count = number / value
      roman += literals[index] * count
      number -= value * count
    end
    roman
  end
end
