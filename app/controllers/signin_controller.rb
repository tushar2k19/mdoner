class SigninController < ApplicationController
  # before_action :authorize_access_request!, only: [:destroy]

  def create
    Rails.logger.info "Signin attempt for email: #{params[:email]}"
    user = User.find_by(email: params[:email])
    if user&.authenticate(params[:password])
      Rails.logger.info "User authenticated successfully: #{user.id}"
      payload = { user_id: user.id }
      session = JWTSessions::Session.new(payload: payload, refresh_by_access_allowed: true)
      tokens = session.login

      signin_info = {
        id: user.id,
        first_name: user.first_name,
        last_name: user.last_name,
        username: "#{user.first_name}" + " #{user.last_name}",
        role: user.role,
        email: user.email,
      }.to_json

      data_to_encrypt = {
        user_info: signin_info,
        csrf_token: tokens[:csrf]
      }
      iv = SecureRandom.random_bytes(16)

      cipher = OpenSSL::Cipher.new('aes-256-cbc')
      cipher.encrypt
      cipher.key = ENCRYPTION_KEY
      cipher.iv = iv
      encrypted_data = cipher.update(data_to_encrypt.to_json) + cipher.final
      combined = iv + encrypted_data
      encoded_data = Base64.strict_encode64(combined)

      # Set JWT cookies with proper domain and security settings
      cookie_options = {
        httponly: true,
        secure: Rails.env.production?,
        same_site: Rails.env.production? ? :none : :lax,
        path: '/'
      }
      
      # Set domain for production - use nil to allow cross-subdomain cookies
      if Rails.env.production?
        # Don't set domain to allow cookies to work across different domains
        # The browser will handle this automatically
      end

      response.set_cookie(JWTSessions.access_cookie,
                          value: tokens[:access],
                          **cookie_options)

      response.set_cookie('csrf_token',
                          value: tokens[:csrf],
                          httponly: false,
                          secure: Rails.env.production?,
                          same_site: Rails.env.production? ? :none : :lax,
                          path: '/')

      render json: { success: true, data: encoded_data }
    else
      Rails.logger.warn("Invalid login attempt for email: #{params[:email]}")
      render json: { error: 'Invalid email or password' }, status: :unauthorized
    end
  end

  def destroy
    begin
      session = JWTSessions::Session.new(payload: payload)
      session.flush_by_access_payload
      
      cookie_options = {
        path: '/'
      }
      
      if Rails.env.production?
        cookie_options[:domain] = '.railway.app'
      end
      
      response.delete_cookie(JWTSessions.access_cookie, **cookie_options)
      response.delete_cookie('csrf_token', **cookie_options)
      response.delete_cookie('user_info', **cookie_options)

      render json: { message: 'Logged out successfully' }, status: :ok
    rescue JWTSessions::Errors::Unauthorized => e
      Rails.logger.info("Failed to logout: #{e.message}")
      render json: { error: 'Not authorized' }, status: :unauthorized
    end
  end

end
