# frozen_string_literal: true

require "json"
require "net/http"
require "uri"

class ResendClient
  class Error < StandardError; end

  API_URL = "https://api.resend.com/emails"

  def initialize(api_key: ENV.fetch("RESEND_EMAIL_API"))
    @api_key = api_key
  end

  def send_email!(from:, to:, subject:, html:, text: nil, headers: {})
    body = {
      from: from,
      to: Array(to),
      subject: subject,
      html: html
    }
    body[:text] = text if text.present?
    body[:headers] = headers if headers.present?

    uri = URI.parse(API_URL)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true
    request = Net::HTTP::Post.new(uri.request_uri)
    request["Authorization"] = "Bearer #{@api_key}"
    request["Content-Type"] = "application/json"
    request.body = body.to_json

    response = http.request(request)
    parsed = parse_body(response.body)
    return parsed if response.code.to_i.between?(200, 299)

    raise Error, "Resend send failed (status=#{response.code}): #{response.body}"
  end

  private

  def parse_body(raw)
    return {} if raw.blank?

    JSON.parse(raw)
  rescue JSON::ParserError
    { "raw" => raw.to_s }
  end
end
