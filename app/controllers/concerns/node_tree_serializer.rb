module NodeTreeSerializer
  extend ActiveSupport::Concern

  # Pre-calculate all display counters and formatted displays in one pass
  def calculate_display_counters(tree_nodes)
    # Recursive helper to calculate counters
    calculate_for_tree = lambda do |nodes|
      # Group siblings by list_style
      nodes_by_style = nodes.group_by { |item| item[:node].list_style }
      
      nodes_by_style.each do |list_style, style_nodes|
        # Sort by position within each style group
        sorted_nodes = style_nodes.sort_by { |item| item[:node].position }
        
        # Assign counter to each node in this group
        sorted_nodes.each_with_index do |tree_item, index|
          counter_position = index + 1
          counter = case list_style
                    when 'decimal'
                      counter_position.to_s
                    when 'lower-alpha'
                      (96 + counter_position).chr # a, b, c...
                    when 'lower-roman'
                      to_roman_numeral(counter_position).downcase
                    when 'bullet'
                      '•'
                    else
                      counter_position.to_s
                    end
          
          tree_item[:display_counter] = counter
          
          # Also calculate formatted_display
          node = tree_item[:node]
          indent = '  ' * (node.level - 1)
          
          # Simplified strip_html_tags logic matching ActionNode
          content_without_html = node.content.to_s.gsub(/<[^>]*>/, '').strip
          display_content = (node.node_type == 'rich_text' || node.node_type == 'table') ? content_without_html : node.content
          
          tree_item[:formatted_display] = case list_style
                                          when 'bullet'
                                            "#{indent}#{counter} #{display_content}"
                                          else
                                            "#{indent}#{counter}. #{display_content}"
                                          end
          
          # Recursively process children
          calculate_for_tree.call(tree_item[:children]) if tree_item[:children].any?
        end
      end
    end
    
    calculate_for_tree.call(tree_nodes)
    tree_nodes
  end

  def to_roman_numeral(number)
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
