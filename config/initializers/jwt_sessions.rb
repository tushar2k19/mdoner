JWTSessions.encryption_key = Rails.application.credentials.secret_key_base || "f1a2b3c4d5e6f7g8h9i0j1k2l3m4n5o6"
JWTSessions.access_exp_time = 3600 # 1 hour
JWTSessions.refresh_exp_time = 604800 # 1 week

# Configure JWT sessions for production
if Rails.env.production?
  JWTSessions.access_cookie = 'access_token'
  JWTSessions.refresh_cookie = 'refresh_token'
  JWTSessions.csrf_cookie = 'csrf_token'
  
  # Cookie settings for production
  JWTSessions.cookie_options = {
    secure: true,
    same_site: :none,
    httponly: true
  }
end
