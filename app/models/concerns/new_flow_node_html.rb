# frozen_string_literal: true

# Shared HTML rendering for meeting-dashboard draft and snapshot nodes (duck-typed like ActionNode).
module NewFlowNodeHtml
  extend ActiveSupport::Concern

  def html_content
    case node_type
    when "rich_text", "table"
      content
    else
      CGI.escapeHTML(content.to_s)
    end
  end

  def display_counter
    sibs = siblings_with_same_style.where("position <= ?", position).order(:position)
    counter_position = sibs.count
    case list_style
    when "decimal"
      counter_position.to_s
    when "lower-alpha"
      (96 + counter_position).chr
    when "lower-roman"
      to_roman(counter_position).downcase
    when "bullet"
      "•"
    else
      counter_position.to_s
    end
  end

  def html_formatted_display(precalculated_counter = nil)
    counter = precalculated_counter || display_counter
    content_html = html_content
    review_date_html = ""
    if review_date.present?
      formatted_date = review_date.strftime("%d/%m")
      is_today = review_date.to_date == Date.current
      date_classes = ["review-date"]
      date_classes << "today" if is_today
      review_date_html = %( <span class="#{date_classes.join(' ')}">#{formatted_date}</span>)
    end
    css_classes = ["action-node", "level-#{level}", "style-#{list_style}"]
    css_classes << "completed" if completed
    css_classes << "has-reviewer" if reviewer_id.present?
    reviewer_data = ""
    reviewer_html = ""
    if reviewer_id.present? && respond_to?(:reviewer) && reviewer
      reviewer_data = %( data-reviewer-id="#{reviewer_id}" data-reviewer-name="#{CGI.escapeHTML(reviewer.full_name)}")
      reviewer_html = %(<span class="reviewer-badge-parallel" data-reviewer-id="#{reviewer_id}">#{reviewer.full_name}</span>)
    end
    stable_attr = if respond_to?(:stable_node_id) && stable_node_id.present?
                    %( data-stable-node-id="#{CGI.escapeHTML(stable_node_id.to_s)}")
                  else
                    ""
                  end
    result_html = if list_style == "bullet"
                    %(<div id="action-node-#{id}" data-node-id="#{id}"#{stable_attr} class="#{css_classes.join(' ')}"#{reviewer_data}>
                        <span class="node-marker">#{counter}</span>
                        <span class="node-content">#{content_html}#{review_date_html}</span>
                        #{reviewer_html}
                      </div>)
                  else
                    %(<div id="action-node-#{id}" data-node-id="#{id}"#{stable_attr} class="#{css_classes.join(' ')}"#{reviewer_data}>
                        <span class="node-marker">#{counter}.</span>
                        <span class="node-content">#{content_html}#{review_date_html}</span>
                        #{reviewer_html}
                      </div>)
                  end
    result_html.html_safe
  rescue StandardError => e
    Rails.logger.error "Error rendering HTML for node #{id}: #{e.message}"
    truncated_content = content.to_s.truncate(200, omission: "... [Error rendering content]")
    "Error: Failed to render content. Original content preview: \"#{truncated_content}\"".html_safe
  end

  private

  def to_roman(number)
    return "" if number <= 0
    values = [1000, 900, 500, 400, 100, 90, 50, 40, 10, 9, 5, 4, 1]
    literals = %w[M CM D CD C XC L XL X IX V IV I]
    roman = ""
    values.each_with_index do |value, index|
      count = number / value
      roman += literals[index] * count
      number -= value * count
    end
    roman
  end
end
