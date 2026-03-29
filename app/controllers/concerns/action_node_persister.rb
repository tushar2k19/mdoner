module ActionNodePersister
  extend ActiveSupport::Concern

  included do
  end

  def create_action_nodes_for_version(version, nodes_data)
    # Handle both flat and hierarchical node structures
    flat_nodes = flatten_node_structure(nodes_data)
    
    # Create nodes in order, handling parent relationships
    node_mapping = {} # Map temp IDs to real IDs
    sibling_positions = Hash.new(0) # Track positions in memory
    
    flat_nodes.each do |node_data|
      # Handle parent relationship
      parent_node = nil
      if node_data['parent_id'] && node_data['parent_id'].to_i < 0
        # Temporary parent ID - look up in mapping
        parent_node = node_mapping[node_data['parent_id'].to_i]
      elsif node_data['parent_id'] && node_data['parent_id'].to_i > 0
        # Real parent ID
        parent_node = version.all_action_nodes.find_by(id: node_data['parent_id'])
      end
      
      # Use in-memory position tracking to avoid N+1 SELECT MAX queries
      parent_id_key = parent_node&.id
      sibling_positions[parent_id_key] += 1
      
      new_node = version.add_action_node(
        content: node_data['content'],
        level: node_data['level'] || 1,
        list_style: node_data['list_style'] || 'decimal',
        node_type: node_data['node_type'] || 'point',
        parent: parent_node,
        review_date: node_data['review_date'],
        completed: node_data['completed'] || false,
        reviewer_id: node_data['reviewer_id'],
        position: sibling_positions[parent_id_key] # Pass position directly
      )
      
      # Store mapping for temporary IDs
      if node_data['id'] && node_data['id'].to_i < 0
        node_mapping[node_data['id'].to_i] = new_node
      end
    end
  end

  # Delta apply to avoid delete-all + recreate flow.
  # Source of truth for ordering is payload order within siblings.
  def apply_action_nodes_delta(version, nodes_data)
    flat_nodes = flatten_node_structure(nodes_data)

    existing_nodes = version.all_action_nodes.to_a
    existing_by_id = existing_nodes.index_by(&:id)
    existing_by_stable_id = existing_nodes.index_by(&:stable_node_id)
    temp_to_created = {}
    seen_existing_ids = {}
    sibling_positions = Hash.new(0)

    flat_nodes.each do |node_data|
      node_id = node_data['id']&.to_i
      stable_node_id = node_data['stable_node_id']
      parent_ref = node_data['parent_id']
      parent_ref_i = parent_ref.nil? ? nil : parent_ref.to_i

      parent_node = resolve_delta_parent_node!(
        version: version,
        parent_ref_i: parent_ref_i,
        existing_by_id: existing_by_id,
        existing_by_stable_id: existing_by_stable_id,
        temp_to_created: temp_to_created,
        flat_nodes: flat_nodes
      )

      sibling_key = parent_ref_i
      sibling_positions[sibling_key] += 1
      payload_position = sibling_positions[sibling_key]

      attrs = {
        content: node_data['content'],
        level: node_data['level'] || 1,
        list_style: node_data['list_style'] || 'decimal',
        node_type: node_data['node_type'] || 'point',
        review_date: node_data['review_date'],
        completed: node_data['completed'] || false,
        reviewer_id: node_data['reviewer_id'],
        parent_id: parent_node&.id,
        position: payload_position
      }

      existing = nil
      if stable_node_id.present?
        existing = existing_by_stable_id[stable_node_id]
      end
      if existing.nil? && node_id && node_id > 0
        existing = existing_by_id[node_id]
      end

      if existing
        existing.assign_attributes(attrs)
        existing.save! if existing.changed?
        seen_existing_ids[existing.id] = true
      else
        created = version.add_action_node(
          content: attrs[:content],
          level: attrs[:level],
          list_style: attrs[:list_style],
          node_type: attrs[:node_type],
          parent: parent_node,
          review_date: attrs[:review_date],
          completed: attrs[:completed],
          reviewer_id: attrs[:reviewer_id],
          position: attrs[:position]
        )
        # Preserve stable_node_id if provided by the client (for cross-version merge)
        if stable_node_id.present?
          created.update_column(:stable_node_id, stable_node_id)
        end

        temp_to_created[node_id] = created if node_id && node_id < 0
      end
    end

    to_delete = existing_nodes.reject { |node| seen_existing_ids[node.id] }
    to_delete.sort_by { |node| -node.level }.each(&:destroy!)
  end

  def resolve_delta_parent_node!(version:, parent_ref_i:, existing_by_id:, existing_by_stable_id:, temp_to_created:, flat_nodes:)
    return nil if parent_ref_i.nil?

    if parent_ref_i < 0
      parent_node = temp_to_created[parent_ref_i]
      unless parent_node
        version.errors.add(:base, "Unresolved temporary parent id #{parent_ref_i}")
        raise ActiveRecord::RecordInvalid.new(version)
      end
      return parent_node
    end

    # 1. Try resolving by numeric ID directly (fastest, standard flow)
    parent_node = existing_by_id[parent_ref_i]
    return parent_node if parent_node

    # 2. If missing by ID (e.g. merge from another version), find parent's stable ID from payload
    if flat_nodes
      parent_data = flat_nodes.find { |n| n['id']&.to_i == parent_ref_i }
      if parent_data && parent_data['stable_node_id'].present?
        parent_node = existing_by_stable_id[parent_data['stable_node_id']]
        return parent_node if parent_node
      end
    end

    version.errors.add(:base, "Unresolved existing parent id #{parent_ref_i}")
    raise ActiveRecord::RecordInvalid.new(version)
  end
  
  def flatten_node_structure(nodes_data)
    # If nodes_data is already flat, return as is
    return nodes_data unless nodes_data.first&.key?('children')
    
    # Otherwise, flatten hierarchical structure
    flat_nodes = []
    nodes_data.each do |node_item|
      if node_item.key?('node')
        # Tree structure: {node: {...}, children: [...]}
        flat_nodes << node_item['node']
        flat_nodes.concat(flatten_node_structure(node_item['children'])) if node_item['children']&.any?
      elsif node_item.key?('content')
        # Structure sometimes used in review_controller
        node_copy = node_item.except('children')
        flat_nodes << node_copy
        flat_nodes.concat(flatten_node_structure(node_item['children'])) if node_item['children']&.any?
      else
        # Already flat structure
        flat_nodes << node_item
      end
    end
    flat_nodes
  end
end