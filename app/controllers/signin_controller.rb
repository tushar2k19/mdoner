class SigninController < ApplicationController
  # before_action :authorize_access_request!, only: [:destroy]

  def create
    user = User.find_by(email: params[:email])
    if user&.authenticate(params[:password])
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

      # response.set_cookie(JWTSessions.access_cookie,
      #                     value: tokens[:access],
      #                     httponly: true,
      #                     secure: Rails.env.production?,
      #                     same_site: Rails.env.production? ? :none : :lax,
      #                     path: '/',
                          # domain: Rails.env.production? ? "mdoner-production.up.railway.app" : "localhost")

                          render json: { success: true, access: tokens[:access], csrf: tokens[:csrf], data: encoded_data }
    else
      Rails.logger.warn("Invalid login attempt for email: #{params[:email]}")
      render json: { error: 'Invalid email or password' }, status: :unauthorized
    end
  end

  def destroy
    begin
      session = JWTSessions::Session.new(payload: payload)
      session.flush_by_access_payload
      response.delete_cookie(JWTSessions.access_cookie)
      response.delete_cookie('csrf_token')
      response.delete_cookie('user_info')

      render json: { message: 'Logged out successfully' }, status: :ok
    rescue JWTSessions::Errors::Unauthorized => e
      Rails.logger.info("Failed to logout: #{e.message}")
      render json: { error: 'Not authorized' }, status: :unauthorized
    end
  end

end
