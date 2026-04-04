# frozen_string_literal: true

class NewActionNode < ApplicationRecord
  include NewFlowNodeHtml

  acts_as_paranoid

  belongs_to :new_task, inverse_of: :new_action_nodes
  belongs_to :parent, class_name: "NewActionNode", optional: true, inverse_of: :children
  belongs_to :reviewer, class_name: "User", optional: true
  has_many :children, -> { order(:position) }, class_name: "NewActionNode", foreign_key: :parent_id,
                                                 dependent: :destroy, inverse_of: :parent

  validates :node_type, presence: true,
                        inclusion: { in: %w[paragraph point subpoint subsubpoint table rich_text] }
  validates :list_style, presence: true,
                         inclusion: { in: %w[decimal lower-alpha lower-roman bullet] }
  validates :level, presence: true, numericality: { greater_than: 0 }
  validates :content, presence: true
  validates :position, presence: true

  default_scope { order(position: :asc) }

  before_validation :set_default_position, on: :create
  before_validation :set_stable_node_id, on: :create

  def siblings_with_same_style
    if parent_id
      self.class.unscoped.where(new_task_id: new_task_id, parent_id: parent_id, deleted_at: nil)
             .where(list_style: list_style)
    else
      self.class.unscoped.where(new_task_id: new_task_id, parent_id: nil, deleted_at: nil)
             .where(list_style: list_style)
    end
  end

  private

  def set_stable_node_id
    self.stable_node_id ||= SecureRandom.uuid
  end

  def set_default_position
    return if position.present?
    rel = parent_id ? self.class.unscoped.where(parent_id: parent_id, new_task_id: new_task_id) : self.class.unscoped.where(parent_id: nil, new_task_id: new_task_id)
    self.position = rel.maximum(:position).to_i + 1
  end
end
