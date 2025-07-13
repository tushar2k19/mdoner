class ApplicationController < ActionController::API
  before_action :set_cors_headers

  include JWTSessions::RailsAuthorization
  rescue_from JWTSessions::Errors::Unauthorized, with: :not_authorized

  # Test endpoint to verify authentication
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
      Rails.logger.info "Attempting to get current_user from JWT payload"
      user_id = payload['user_id']
      Rails.logger.info "JWT payload user_id: #{user_id}"
      if user_id
        user = User.find(user_id)
        Rails.logger.info "Found user: #{user.email}"
        user
      else
        Rails.logger.error "No user_id in JWT payload"
        raise JWTSessions::Errors::Unauthorized, "Invalid token payload"
      end
    rescue ActiveRecord::RecordNotFound => e
      Rails.logger.error "User not found for ID: #{user_id}"
      raise JWTSessions::Errors::Unauthorized, "User not found"
    rescue JWTSessions::Errors::Unauthorized => e
      Rails.logger.error "JWT authorization failed: #{e.message}"
      raise e
    rescue => e
      Rails.logger.error "Unexpected error in current_user: #{e.message}"
      raise JWTSessions::Errors::Unauthorized, "Authentication failed"
    end
  end

  def not_authorized
    render json: { error: "Not authorized" }, status: :unauthorized
  end

  def set_cors_headers
    if Rails.env.production?
      # Allow multiple frontend domains
      allowed_origins = [
        'https://mdoner.netlify.app',
        'https://wadii.netlify.app',
        'https://wadi-india.netlify.app'
      ]
      
      origin = request.headers['Origin']
      if allowed_origins.include?(origin)
        response.headers['Access-Control-Allow-Origin'] = origin
        response.headers['Access-Control-Allow-Credentials'] = 'true'
        response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, PATCH, DELETE, OPTIONS'
        response.headers['Access-Control-Allow-Headers'] = 'Origin, Content-Type, Accept, Authorization, X-CSRF-Token'
        response.headers['Access-Control-Expose-Headers'] = 'access-token, expiry, token-type, Authorization'
      end
    else
      # Development: allow all origins
      response.headers['Access-Control-Allow-Origin'] = request.headers['Origin']
      response.headers['Access-Control-Allow-Credentials'] = 'true'
      response.headers['Access-Control-Allow-Methods'] = 'GET, POST, PUT, PATCH, DELETE, OPTIONS'
      response.headers['Access-Control-Allow-Headers'] = 'Origin, Content-Type, Accept, Authorization, X-CSRF-Token'
      response.headers['Access-Control-Expose-Headers'] = 'access-token, expiry, token-type, Authorization'
    end
  end
end
