class ApplicationController < ActionController::API
  before_action :set_cors_headers

  include JWTSessions::RailsAuthorization
  rescue_from JWTSessions::Errors::Unauthorized, with: :not_authorized

  def test_auth
    render json: { 
      success: true, 
      message: 'Authentication working',
      user: {
        id: current_user.id,
        email: current_user.email,
        role: current_user.role
      }
    }
  end

  private
  def current_user
    @current_user ||= begin
      user_id = nil

      # 1. Try to get JWT from Authorization header
      auth_header = request.headers['Authorization']
      if auth_header&.start_with?('Bearer ')
        token = auth_header.split(' ', 2).last
        begin
          payload = JWTSessions::Token.decode(token)
          user_id = payload['user_id']
        rescue
          # Invalid token, fallback to cookie
        end
      end

      # 2. Fallback: Try to get JWT from cookie (default JWTSessions behavior)
      if user_id.nil?
        user_id = payload['user_id'] rescue nil
      end

      user_id ? User.find(user_id) : nil
    end
  end
  def not_authorized
    render json: { error: "Not authorized" }, status: :unauthorized
  end
  def set_cors_headers
    if Rails.env.production?
      # frontend_url = 'https://wadi-india.netlify.app'
      frontend_url = 'https://mdoner.netlify.app'


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
