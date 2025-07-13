class RefreshController < ApplicationController
  # before_action :authorize_refresh_by_access_request!

  def create
    session = JWTSessions::Session.new(payload: payload, refresh_by_access_allowed: true)

    tokens = session.refresh(found_token: access_token)

    # Set JWT cookies with proper domain and security settings
    cookie_options = {
      httponly: true,
      secure: Rails.env.production?,
      same_site: Rails.env.production? ? :none : :lax,
      path: '/'
    }
    
    # Set domain for production
    if Rails.env.production?
      cookie_options[:domain] = '.railway.app'
    end

    response.set_cookie(JWTSessions.access_cookie,
                        value: tokens[:access],
                        **cookie_options)

    response.set_cookie('csrf_token',
                        value: tokens[:csrf],
                        httponly: false,
                        secure: Rails.env.production?,
                        same_site: Rails.env.production? ? :none : :lax,
                        path: '/',
                        domain: Rails.env.production? ? '.railway.app' : nil)

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
