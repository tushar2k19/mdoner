class ApplicationController < ActionController::API
  before_action :set_cors_headers

  include JWTSessions::RailsAuthorization
  rescue_from JWTSessions::Errors::Unauthorized, with: :not_authorized

  private
  def current_user
    @current_user || (User.find(payload['user_id']))#comes from the JWT sessions (line 2)
  end
  def not_authorized
    render json: { error: "Not authorized" }, status: :unauthorized
  end
  def set_cors_headers
    if Rails.env.production?
      # frontend_url = 'https://wadi-india.netlify.app'
      frontend_url = 'https://wadii.netlify.app/'


      # Only set these headers if the request is coming from your frontend
      if request.headers['Origin'] == frontend_url
        response.headers['Access-Control-Allow-Origin'] = frontend_url
        response.headers['Access-Control-Allow-Credentials'] = 'true'
        response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, PATCH, DELETE, OPTIONS'
        response.headers['Access-Control-Allow-Headers'] = 'Origin, Content-Type, Accept, Authorization, X-CSRF-Token'
        response.headers['Access-Control-Expose-Headers'] = 'access-token, expiry, token-type, Authorization'
      end
    end
  end
end
