# app/models/action_node.rb
class ActionNode < ApplicationRecord
  belongs_to :task_version
  belongs_to :parent, class_name: 'ActionNode', optional: true
  has_many :children, class_name: 'ActionNode', foreign_key: 'parent_id'
  has_many :comments, dependent: :destroy

  validates :node_type, presence: true,
            inclusion: { in: %w[paragraph point subpoint subsubpoint]  #add others if necessary (tables, etc).
            }
  accepts_nested_attributes_for :children, allow_destroy: true


  validates :content, presence: true
  validates :position, presence: true
  before_validation :set_default_position, on: :create


  # Automatic sorting
  default_scope { order(position: :asc) }
  before_validation :set_default_position, on: :create

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

  # Automatic position management
  before_create :set_default_position

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

  #
  # def all_children
  #   children.flat_map { |child| [child] + child.all_children }
  # end
  private

  def set_default_position
    self.position ||= siblings.maximum(:position).to_i + 1
  end

  def siblings
    parent ? parent.children : task_version.action_nodes.where(parent_id: nil)
  end
end
