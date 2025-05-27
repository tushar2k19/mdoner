class RefreshController < ApplicationController
  # before_action :authorize_refresh_by_access_request!

  def create
    session = JWTSessions::Session.new(payload: payload, refresh_by_access_allowed: true)

    tokens = session.refresh(found_token: access_token)

    response.set_cookie(JWTSessions.access_cookie,
                        value: tokens[:access],
                        httponly: true,
                        secure: Rails.env.production?,
                        same_site: Rails.env.production? ? :none : :lax,
                        path: '/',
                        domain: Rails.env.production? ? "wadibackend.com" : "localhost")

    response.set_cookie('csrf_token',
                        value: tokens[:csrf],
                        httponly: false,
                        secure: Rails.env.production?,
                        same_site: Rails.env.production? ? :none : :lax,
                        path: '/',
                        domain: Rails.env.production? ? "wadibackend.com" : "localhost")

    render json: { csrf: tokens[:csrf] }
  rescue JWTSessions::Errors::Unauthorized, JWTSessions::Errors::ClaimsVerification => e
    Rails.logger.error("Refresh token error: #{e.message}")
    render json: { error: 'Not authorized' }, status: :unauthorized
  end

  private

  def access_token
    request.cookie_jar.signed[JWTSessions.access_cookie]
  end
end
