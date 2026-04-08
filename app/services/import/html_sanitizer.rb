# frozen_string_literal: true

module Import
  class HtmlSanitizer
    # Keep this list small and purpose-built for dashboards.
    ALLOWED_TAGS = %w[
      b strong i em u br p div span font
      table thead tbody tr td th colgroup col
      sup sub
    ].freeze

    # Allow minimal attributes; table layout relies on inline styles.
    ALLOWED_ATTRS_BY_TAG = {
      'table' => %w[class style dir width cellpadding cellspacing border],
      'colgroup' => %w[style span width],
      'col' => %w[style span width align valign],
      'thead' => %w[style],
      'tbody' => %w[style],
      'tr' => %w[style valign],
      'td' => %w[style valign align width height bgcolor colspan rowspan],
      'th' => %w[style valign align width height bgcolor colspan rowspan],
      'span' => %w[style lang],
      'font' => %w[color face size style],
      'p' => %w[style align class],
      'div' => %w[style title],
    }.freeze

    def self.sanitize_html(html)
      return '' if html.nil?
      frag = Nokogiri::HTML::DocumentFragment.parse(html.to_s)
      sanitize_node!(frag)
      frag.to_html
    end

    def self.text(html)
      return '' if html.nil?
      Nokogiri::HTML(html.to_s).text.strip
    end

    def self.sanitize_node!(node)
      node.children.each do |child|
        if child.element?
          unless ALLOWED_TAGS.include?(child.name)
            # Replace unknown tags with their children (keep text content).
            child.replace(child.children)
            next
          end

          allowed_attrs = ALLOWED_ATTRS_BY_TAG.fetch(child.name, [])
          child.attribute_nodes.each do |attr|
            next if allowed_attrs.include?(attr.name)
            child.remove_attribute(attr.name)
          end

          # Strip event handlers even if whitelisted accidentally.
          child.attribute_nodes.each do |attr|
            child.remove_attribute(attr.name) if attr.name.start_with?('on')
          end

          sanitize_node!(child)
        elsif child.comment?
          child.remove
        else
          # text nodes are fine
        end
      end
    end

    private_class_method :sanitize_node!
  end
end

