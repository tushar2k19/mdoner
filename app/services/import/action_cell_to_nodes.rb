# frozen_string_literal: true

module Import
  class ActionCellToNodes
    Node = Struct.new(:id, :parent_id, :level, :list_style, :node_type, :content, :position, keyword_init: true)

    def initialize(action_cell_node)
      @cell = action_cell_node
      @next_temp_id = -1
      @flat = []
    end

    def self.parse(action_cell_node)
      new(action_cell_node).parse
    end

    def parse
      return [] unless @cell

      # Prefer lists when present; otherwise treat as a single rich-text root node.
      top_lists = @cell.element_children.select { |n| n.name == 'ol' || n.name == 'ul' }
      if top_lists.any?
        top_lists.each { |list| parse_list(list, parent_id: nil, level: 1) }

        # LibreOffice may place tables after the list (siblings in the action cell).
        trailing_tables = @cell.element_children.select { |n| n.name == 'table' }
        if trailing_tables.any?
          position = (@flat.select { |n| n.parent_id.nil? }.map(&:position).max || 0)
          trailing_tables.each do |tbl|
            position += 1
            html = begin
              Import::HtmlTableToResizableTable.convert(tbl)
            rescue Import::HtmlTableToResizableTable::UnsupportedTable
              Import::HtmlSanitizer.sanitize_html(tbl.to_html)
            end
            add_node(parent_id: nil, level: 1, list_style: 'decimal', node_type: 'rich_text', content: html, position: position)
          end
        end
      else
        # If content is mostly a table or paragraphs, wrap as one node.
        html = Import::HtmlSanitizer.sanitize_html(@cell.inner_html).strip
        add_node(parent_id: nil, level: 1, list_style: 'decimal', node_type: 'rich_text', content: html, position: 1) if html.present?
      end

      @flat.map do |n|
        {
          id: n.id,
          parent_id: n.parent_id,
          level: n.level,
          list_style: n.list_style,
          node_type: n.node_type,
          content: n.content,
          review_date: nil,
          completed: false,
          has_rich_formatting: true
        }
      end
    end

    private

    def parse_list(list_node, parent_id:, level:)
      list_style = list_style_for(list_node)
      position = 0

      list_node.element_children.select { |n| n.name == 'li' }.each do |li|
        position += 1

        # Extract li's own content excluding nested lists; keep tables.
        own_html = li_own_html(li)
        node_id = add_node(
          parent_id: parent_id,
          level: level,
          list_style: list_style,
          node_type: 'rich_text',
          content: own_html,
          position: position
        )

        # Recurse into nested lists, if any.
        li.element_children.select { |n| n.name == 'ol' || n.name == 'ul' }.each do |child_list|
          parse_list(child_list, parent_id: node_id, level: level + 1)
        end
      end
    end

    def li_own_html(li)
      clone = li.dup
      clone.element_children.select { |n| n.name == 'ol' || n.name == 'ul' }.each(&:remove)

      # Convert any embedded tables to resizable format.
      clone.css('table').each do |tbl|
        begin
          tbl.replace(Import::HtmlTableToResizableTable.convert(tbl))
        rescue Import::HtmlTableToResizableTable::UnsupportedTable
          # Fallback: keep a sanitized original table HTML.
          tbl.replace(Import::HtmlSanitizer.sanitize_html(tbl.to_html))
        end
      end

      html = Import::HtmlSanitizer.sanitize_html(clone.inner_html).strip
      html
    end

    def list_style_for(list_node)
      return 'bullet' if list_node.name == 'ul'
      t = list_node['type'].to_s.strip.downcase
      return 'lower-alpha' if t == 'a'
      return 'lower-roman' if t == 'i'
      'decimal'
    end

    def add_node(parent_id:, level:, list_style:, node_type:, content:, position:)
      cid = content.to_s.strip
      # Avoid creating empty nodes; LibreOffice often emits whitespace.
      return nil if cid.empty?

      id = @next_temp_id
      @next_temp_id -= 1
      @flat << Node.new(
        id: id,
        parent_id: parent_id,
        level: level,
        list_style: list_style,
        node_type: node_type,
        content: cid,
        position: position
      )
      id
    end
  end
end

