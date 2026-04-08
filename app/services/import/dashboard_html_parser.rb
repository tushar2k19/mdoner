# frozen_string_literal: true

module Import
  class DashboardHtmlParser
    HeaderMatch = Struct.new(:sn, :sector, :description, :action, :original_date, :responsibility, :review_date, keyword_init: true)

    def self.parse(html, limit: nil)
      new(html, limit: limit).parse
    end

    def initialize(html, limit: nil)
      @html = html.to_s
      @limit = limit&.to_i
    end

    def parse
      doc = Nokogiri::HTML(@html)
      table, header_map = locate_main_table(doc)
      raise ArgumentError, 'Could not locate main dashboard table' unless table && header_map

      extracted = []

      # Only consider rows that belong to the main table, not nested tables inside cells.
      table.xpath('./tr|./thead/tr|./tbody/tr').each do |tr|
        tds = tr.xpath('./td')
        next if tds.empty?

        sn = extract_sn(tds[header_map.sn])
        next unless sn

        sector = Import::HtmlSanitizer.text(tds[header_map.sector]&.inner_html)
        description = Import::HtmlSanitizer.text(tds[header_map.description]&.inner_html)
        responsibility = Import::HtmlSanitizer.text(tds[header_map.responsibility]&.inner_html)

        action_cell = tds[header_map.action]
        nodes = Import::ActionCellToNodes.parse(action_cell)

        extracted << {
          sn: sn,
          sector_division: sector,
          description: description,
          responsibility: responsibility,
          nodes: nodes
        }

        break if @limit && extracted.size >= @limit
      end

      extracted
    end

    private

    def locate_main_table(doc)
      doc.css('table').each do |tbl|
        header_map = header_indices_for(tbl)
        return [tbl, header_map] if header_map
      end
      [nil, nil]
    end

    def header_indices_for(table)
      header_row = table.css('tr').find do |tr|
        text = tr.text.gsub(/\s+/, ' ').strip.downcase
        has_sn_like = text.match?(/\b(s\.?\s*i\.?|s\.?\s*n\.?|sl\.?\s*no\.?)\b/)
        has_sn_like && text.include?('sector') && text.include?('description') && text.include?('action') && text.include?('responsibility')
      end
      return nil unless header_row

      cells = header_row.css('th,td').to_a
      idx = ->(re) { cells.find_index { |c| c.text.to_s.gsub(/\s+/, ' ').strip.downcase.match?(re) } }

      sn = idx.call(/\A(sn|s\.?\s*n\.?|si|s\.?\s*i\.?|sl\.?\s*no\.?)\z/)
      sector = idx.call(/sector/)
      description = idx.call(/description/)
      action = idx.call(/action/)
      original_date = idx.call(/original/)
      responsibility = idx.call(/responsibility/)
      review_date = idx.call(/review/)

      required = [sn, sector, description, action, responsibility]
      return nil if required.any?(&:nil?)

      HeaderMatch.new(
        sn: sn,
        sector: sector,
        description: description,
        action: action,
        original_date: original_date,
        responsibility: responsibility,
        review_date: review_date
      )
    end

    def extract_sn(cell)
      return nil unless cell

      # Common format: plain numeric text in the first column.
      sn_text = cell.text.to_s.strip
      return sn_text.to_i if sn_text.match?(/\A\d+\z/)

      # LibreOffice variant: first column rendered as ordered list with empty <li>,
      # where serial number is encoded in <ol start="N">.
      ol = cell.at_css('ol')
      return nil unless ol

      start = ol['start'].to_s.strip
      return start.to_i if start.match?(/\A\d+\z/)

      # Default ordered list start is 1 when not specified.
      ol.at_css('li') ? 1 : nil
    end
  end
end

