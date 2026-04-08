# frozen_string_literal: true

module Import
  class HtmlTableToResizableTable
    class UnsupportedTable < StandardError; end

    DEFAULT_TABLE_STYLE = 'width: 100%; border-collapse: collapse;'.freeze
    HEADER_STYLE = 'border: 1px solid #ddd; padding: 8px; background-color: #f2f2f2;'.freeze
    CELL_STYLE = 'border: 1px solid #ddd; padding: 8px;'.freeze
    PRESERVE_TABLE_CLASS = 'dashboard-import-table'.freeze
    PRESERVE_TABLE_WRAPPER_STYLE = 'overflow-x: auto; max-width: 100%;'.freeze

    # Word/LibreOffice exports often use rowspan/colspan, colgroup/col, or nested tables.
    # Flattening those into a simple grid destroys the layout; keep sanitized HTML instead.
    def self.complex_layout_table?(table_node)
      return false unless table_node&.name == 'table'

      table_node.css('[rowspan],[colspan]').any? ||
        table_node.css('td table, th table').any? ||
        table_node.at_css('colgroup, col').present?
    end

    def self.convert_or_preserve(table_node)
      raise ArgumentError, 'expected <table> node' unless table_node&.name == 'table'

      if complex_layout_table?(table_node)
        preserve_layout_table(table_node)
      else
        convert(table_node)
      end
    end

    def self.preserve_layout_table(table_node)
      raw = table_node.to_html
      sanitized = Import::HtmlSanitizer.sanitize_html(raw)
      frag = Nokogiri::HTML::DocumentFragment.parse(sanitized)
      tbl = frag.at_css('table')
      return sanitized unless tbl

      normalize_complex_table_node!(tbl, wrap_for_scroll: true)

      frag.to_html
    end

    # Normalize complex merged-cell tables in arbitrary rich-text fragments.
    # Used for paste/save paths so they behave like import-preserved tables.
    def self.normalize_complex_tables_in_html(html)
      return '' if html.nil?
      return html.to_s if html.to_s.empty?

      frag = Nokogiri::HTML::DocumentFragment.parse(html.to_s)
      changed = false

      frag.css('table').to_a.each do |table|
        next unless complex_layout_table?(table)

        changed = true if normalize_complex_table_node!(table, wrap_for_scroll: true)
      end

      changed ? frag.to_html : html.to_s
    end

    def self.convert(table_node)
      raise ArgumentError, 'expected <table> node' unless table_node&.name == 'table'

      if complex_layout_table?(table_node)
        raise UnsupportedTable, 'use convert_or_preserve for complex tables'
      end

      rows = table_node.css('tr').map do |tr|
        tr.css('th,td').map { |cell| sanitize_cell_html(cell) }
      end

      rows.reject!(&:empty?)
      raise UnsupportedTable, 'empty table' if rows.empty?

      headers = rows.first
      body_rows = rows.drop(1)

      html = +''
      html << %(<table class="resizable-table" style="#{DEFAULT_TABLE_STYLE}">\n)
      html << "  <thead>\n    <tr>\n"
      headers.each do |h|
        html << %(      <th style="#{HEADER_STYLE}">#{h}</th>\n)
      end
      html << "    </tr>\n  </thead>\n"
      html << "  <tbody>\n"
      body_rows.each do |row|
        html << "    <tr>\n"
        row.each do |c|
          html << %(      <td style="#{CELL_STYLE}">#{c}</td>\n)
        end
        html << "    </tr>\n"
      end
      html << "  </tbody>\n</table>"
      html
    end

    def self.sanitize_cell_html(cell)
      # Keep lightweight inline formatting, strip nested tables/lists.
      clone = cell.dup
      clone.css('table,ol,ul').remove
      Import::HtmlSanitizer.sanitize_html(clone.inner_html).strip
    end

    def self.normalize_complex_table_node!(table_node, wrap_for_scroll:)
      return false unless table_node&.name == 'table'

      changed = false

      classes = table_node['class'].to_s.split(/\s+/).reject(&:blank?)
      unless classes.include?(PRESERVE_TABLE_CLASS)
        classes << PRESERVE_TABLE_CLASS
        table_node['class'] = classes.join(' ')
        changed = true
      end

      existing_style = table_node['style'].to_s.strip
      merged_style = [existing_style.presence, 'border-collapse: collapse; table-layout: auto; max-width: 100%;'].compact.join(' ')
      if merged_style != existing_style
        table_node['style'] = merged_style
        changed = true
      end

      changed = true if remove_empty_rows!(table_node)

      if wrap_for_scroll
        parent = table_node.parent
        parent_style = parent&.element? ? parent['style'].to_s : ''
        parent_scroll_wrap = parent&.name == 'div' && parent_style.include?('overflow-x: auto')
        unless parent_scroll_wrap
          wrapper = Nokogiri::XML::Node.new('div', table_node.document)
          wrapper['style'] = PRESERVE_TABLE_WRAPPER_STYLE
          table_node.replace(wrapper)
          wrapper.add_child(table_node)
          changed = true
        end
      end

      changed
    end

    def self.remove_empty_rows!(table_node)
      removed = false
      table_node.css('tr').to_a.each do |tr|
        has_cells = tr.element_children.any? { |child| child.name == 'td' || child.name == 'th' }
        next if has_cells

        tr.remove
        removed = true
      end
      removed
    end

    private_class_method :sanitize_cell_html, :normalize_complex_table_node!, :remove_empty_rows!
  end
end

