# frozen_string_literal: true

module Import
  class HtmlTableToResizableTable
    class UnsupportedTable < StandardError; end

    DEFAULT_TABLE_STYLE = 'width: 100%; border-collapse: collapse;'.freeze
    HEADER_STYLE = 'border: 1px solid #ddd; padding: 8px; background-color: #f2f2f2;'.freeze
    CELL_STYLE = 'border: 1px solid #ddd; padding: 8px;'.freeze

    def self.convert(table_node)
      raise ArgumentError, 'expected <table> node' unless table_node&.name == 'table'

      if table_node.css('[rowspan],[colspan]').any?
        raise UnsupportedTable, 'rowspan/colspan not supported in v1'
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

    private_class_method :sanitize_cell_html
  end
end

