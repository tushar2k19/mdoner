# frozen_string_literal: true

require "erb"
require "uri"

class MeetingPackNotificationEmailJob < ApplicationJob
  queue_as :default

  retry_on ResendClient::Error, wait: :polynomially_longer, attempts: 3

  def self.email_delivery_enabled?
    ActiveModel::Type::Boolean.new.cast(ENV.fetch("ENABLE_NOTIFICATION_EMAILS", "false"))
  end

  def perform(meeting_pack_notification_id)
    return unless self.class.email_delivery_enabled?

    notification = MeetingPackNotification.includes(:user).find_by(id: meeting_pack_notification_id)
    return unless notification
    return if notification.emailed_at.present?

    recipient = resolve_recipient(notification)
    return if recipient.blank?

    resend_client.send_email!(
      from: from_email,
      to: recipient,
      subject: build_subject(notification),
      html: build_html(notification),
      text: build_text(notification)
    )

    notification.update_column(:emailed_at, Time.current)
  end

  private

  def resend_client
    @resend_client ||= ResendClient.new
  end

  def from_email
    ENV.fetch("RESEND_EMAIL_FROM", "onboarding@resend.dev")
  end

  def resolve_recipient(notification)
    ENV["DEMO_NOTIFICATION_EMAIL_TO"].presence || notification.user&.email
  end

  def build_subject(notification)
    payload = payload_hash(notification)
    node_label = payload["node_label"].presence

    case notification.kind
    when MeetingPackNotification::KIND_PACK_ASSIGNMENT_CREATED
      node_label.present? ? "Review input requested for Node #{node_label}" : "Review input requested"
    when MeetingPackNotification::KIND_HUB_REMINDER_PENDING
      node_label.present? ? "Reminder: pending inputs for Node #{node_label}" : "Reminder: pending reviewer inputs"
    when MeetingPackNotification::KIND_DASHBOARD_NODE_COMMENT_FOR_ASSIGNEES
      node_label.present? ? "New comment update for Node #{node_label}" : "New comment update on assigned node"
    else
      "MDONER dashboard notification"
    end
  end

  def build_html(notification)
    payload = payload_hash(notification)
    link = deep_link(notification)
    body = ERB::Util.html_escape(notification.body.to_s)
    category_label, accent_color = category_and_accent(notification.kind)
    preview_line = preview_text(notification.kind, payload)
    node_label = payload["node_label"].presence || "Node update"
    sector = payload["sector_division"].presence || "Sector not provided"
    version = payload["new_dashboard_version_id"].presence || "N/A"

    cta_html = if link.present?
                 <<~HTML
                   <tr>
                     <td style="padding: 0 32px 20px 32px;">
                       <a href="#{ERB::Util.html_escape(link)}" style="display:inline-block;background:#{accent_color};color:#ffffff;text-decoration:none;font-weight:700;font-size:14px;line-height:20px;padding:12px 20px;border-radius:8px;">
                         Open Final Dashboard
                       </a>
                     </td>
                   </tr>
                 HTML
               else
                 ""
               end

    fallback_html = if link.present?
                      <<~HTML
                        <tr>
                          <td style="padding: 0 32px 26px 32px;color:#475569;font-size:12px;line-height:18px;">
                            If the button does not work, copy this link:<br/>
                            <a href="#{ERB::Util.html_escape(link)}" style="color:#0f5fd3;text-decoration:underline;word-break:break-all;">#{ERB::Util.html_escape(link)}</a>
                          </td>
                        </tr>
                      HTML
                    else
                      ""
                    end

    <<~HTML
      <!DOCTYPE html>
      <html lang="en">
      <head>
        <meta charset="UTF-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1.0" />
        <title>#{ERB::Util.html_escape(build_subject(notification))}</title>
      </head>
      <body style="margin:0;padding:0;background:#f1f5f9;font-family:'Segoe UI',Roboto,Helvetica,Arial,sans-serif;">
        <div style="display:none;max-height:0;overflow:hidden;opacity:0;color:transparent;">
          #{ERB::Util.html_escape(preview_line)}
        </div>
        <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%" style="background:#f1f5f9;padding:20px 10px;">
          <tr>
            <td align="center">
              <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="620" style="max-width:620px;width:100%;background:#ffffff;border-radius:14px;overflow:hidden;border:1px solid #dbe5f1;">
                <tr>
                  <td style="background:linear-gradient(135deg,#0a2f6b,#114e9d);padding:24px 28px 18px 28px;">
                    <div style="color:#f8fafc;font-size:11px;font-weight:700;letter-spacing:0.8px;text-transform:uppercase;">Ministry of Development of North Eastern Region</div>
                    <div style="margin-top:6px;color:#ffffff;font-size:24px;font-weight:800;letter-spacing:0.4px;">MDONER Dashboard</div>
                    <div style="margin-top:10px;display:inline-block;background:rgba(255,255,255,0.18);border:1px solid rgba(255,255,255,0.35);border-radius:999px;color:#ffffff;font-size:11px;font-weight:700;padding:4px 10px;">
                      #{ERB::Util.html_escape(category_label)}
                    </div>
                  </td>
                </tr>
                <tr>
                  <td style="padding:28px 32px 10px 32px;">
                    <div style="font-size:20px;line-height:28px;color:#0f172a;font-weight:800;margin-bottom:8px;">#{ERB::Util.html_escape(build_subject(notification))}</div>
                    <div style="font-size:14px;line-height:22px;color:#334155;">#{body}</div>
                  </td>
                </tr>
                <tr>
                  <td style="padding: 8px 32px 20px 32px;">
                    <table role="presentation" cellspacing="0" cellpadding="0" border="0" width="100%" style="background:#f8fafc;border:1px solid #e2e8f0;border-radius:10px;">
                      <tr>
                        <td style="padding:14px 16px;">
                          <div style="font-size:12px;line-height:18px;color:#334155;"><strong style="color:#0f172a;">Node:</strong> #{ERB::Util.html_escape(node_label)}</div>
                          <div style="font-size:12px;line-height:18px;color:#334155;margin-top:4px;"><strong style="color:#0f172a;">Sector:</strong> #{ERB::Util.html_escape(sector)}</div>
                          <div style="font-size:12px;line-height:18px;color:#334155;margin-top:4px;"><strong style="color:#0f172a;">Published Version:</strong> ##{ERB::Util.html_escape(version.to_s)}</div>
                        </td>
                      </tr>
                    </table>
                  </td>
                </tr>
                #{cta_html}
                #{fallback_html}
                <tr>
                  <td style="padding: 0 32px 28px 32px;">
                    <div style="height:1px;background:#e2e8f0;margin-bottom:12px;"></div>
                    <div style="font-size:11px;line-height:17px;color:#64748b;">
                      Official communication from MDONER meeting dashboard workflow. This is an automated message for assigned reviewer actions.
                    </div>
                  </td>
                </tr>
              </table>
            </td>
          </tr>
        </table>
      </body>
      </html>
    HTML
  end

  def build_text(notification)
    payload = payload_hash(notification)
    lines = [build_subject(notification), "", notification.body.to_s]
    lines << "Node: #{payload['node_label']}" if payload["node_label"].present?
    lines << "Sector: #{payload['sector_division']}" if payload["sector_division"].present?
    lines << "Version: ##{payload['new_dashboard_version_id']}" if payload["new_dashboard_version_id"].present?
    link = deep_link(notification)
    lines << "Open in Final dashboard: #{link}" if link.present?
    lines.join("\n")
  end

  def deep_link(notification)
    payload = payload_hash(notification)
    version_id = payload["new_dashboard_version_id"].presence
    stable_node_id = payload["stable_node_id"].presence
    return nil if version_id.blank? || stable_node_id.blank?

    base = normalized_frontend_base_url
    return nil if base.blank?

    params = {
      dashboard_version_id: version_id,
      focus_node: stable_node_id,
      focus_task_id: payload["new_task_id"].presence
    }.compact

    "#{base.to_s.chomp('/')}/new-final?#{params.to_query}"
  end

  def payload_hash(notification)
    notification.payload.is_a?(Hash) ? notification.payload : {}
  end

  def category_and_accent(kind)
    case kind
    when MeetingPackNotification::KIND_PACK_ASSIGNMENT_CREATED
      ["Assignment", "#0f5fd3"]
    when MeetingPackNotification::KIND_HUB_REMINDER_PENDING
      ["Reminder", "#c77d00"]
    when MeetingPackNotification::KIND_DASHBOARD_NODE_COMMENT_FOR_ASSIGNEES
      ["Comment Update", "#0d7a5f"]
    else
      ["Notification", "#0f5fd3"]
    end
  end

  def preview_text(kind, payload)
    node_label = payload["node_label"].presence || "assigned node"
    case kind
    when MeetingPackNotification::KIND_PACK_ASSIGNMENT_CREATED
      "You have a new MDONER review assignment on Node #{node_label}."
    when MeetingPackNotification::KIND_HUB_REMINDER_PENDING
      "Reminder: inputs are pending on Node #{node_label}."
    when MeetingPackNotification::KIND_DASHBOARD_NODE_COMMENT_FOR_ASSIGNEES
      "New comments were added on Node #{node_label}."
    else
      "MDONER dashboard update for your attention."
    end
  end

  def normalized_frontend_base_url
    raw = ENV["FRONTEND_APP_URL"].presence || "https://mdoner.netlify.app"
    uri = URI.parse(raw)
    uri.path = ""
    uri.query = nil
    uri.fragment = nil
    uri.to_s
  rescue URI::InvalidURIError
    raw
  end
end
