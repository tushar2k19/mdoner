# frozen_string_literal: true

namespace :db do
  namespace :backfill do
    desc "Ensure NewActionNode (and snapshots) rich_text/table HTML defaults to 12pt (editor font-size picker value 3). Set DRY_RUN=1 to preview."
    task min_font_size_10pt_action_nodes: :environment do
      min_pt = 12.0
      min_html_font_size = 3 # corresponds to "12pt" in the editor font-size picker
      wrapper_marker = "data-force-font-size-3"
      old_wrapper_marker = "data-min-font-size-10pt"
      dry_run = ActiveModel::Type::Boolean.new.cast(ENV.fetch("DRY_RUN", "false"))

      normalize_html = lambda do |html|
        return html if html.blank?

        normalized = html.dup

        # Remove the previous 10pt wrapper (if present) so we can re-wrap in the editor-compatible format.
        normalized = normalized.gsub(
          /<span\b[^>]*#{Regexp.escape(old_wrapper_marker)}[^>]*>(.*?)<\/span>/im,
          '\1'
        )

        # Inline CSS case (e.g. font-size: 7pt / 8px).
        normalized = normalized.gsub(/font-size\s*:\s*(\d+(?:\.\d+)?)\s*(pt|px)\b/i) do |match|
          num = Regexp.last_match(1).to_f
          next match if num >= min_pt

          match.sub(Regexp.last_match(1), min_pt.to_i.to_s)
        end

        # LibreOffice/Word HTML often uses deprecated <font size="2"> tags which can render extremely small.
        # HTML font sizes are 1..7; bump anything <3 to 3 ("12pt" in our font-size picker).
        normalized = normalized.gsub(/<font([^>]*?)\s+size\s*=\s*["']?(\d+)["']?([^>]*)>/i) do
          before_attrs = Regexp.last_match(1)
          size_num = Regexp.last_match(2).to_i
          after_attrs = Regexp.last_match(3)

          next "<font#{before_attrs} size=\"#{size_num}\"#{after_attrs}>" if size_num >= min_html_font_size

          "<font#{before_attrs} size=\"#{min_html_font_size}\"#{after_attrs}>"
        end

        # Enforce a base font-size for any text that doesn't have explicit sizing.
        # Use the same HTML shape as the editor's `execCommand('fontSize', '3')` output: <font size="3">.
        unless normalized.match?(/#{Regexp.escape(wrapper_marker)}/i)
          normalized = %(<font size="#{min_html_font_size}" #{wrapper_marker}>#{normalized}</font>)
        end

        normalized
      end

      models = [
        ["NewActionNode", NewActionNode],
        ["NewDashboardSnapshotActionNode", (defined?(NewDashboardSnapshotActionNode) ? NewDashboardSnapshotActionNode : nil)]
      ].select { |_name, klass| klass.present? }

      models.each do |model_name, model_class|
        scope = model_class.where(node_type: %w[rich_text table])
                           .where("content NOT LIKE ?", "%#{wrapper_marker}%")

        puts "[#{model_name}] candidate rows: #{scope.count}"

        updated = 0
        unchanged = 0

        scope.in_batches(of: 500) do |relation|
          relation.each do |row|
            original = row.content.to_s
            normalized = normalize_html.call(original)

            if normalized == original
              unchanged += 1
              next
            end

            updated += 1
            next if dry_run

            row.update_columns(content: normalized, updated_at: Time.current)
          end
        end

        puts "[#{model_name}] updated: #{updated} | unchanged after normalization: #{unchanged} | dry_run=#{dry_run}"
      end
    end
  end
end

