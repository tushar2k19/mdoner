require 'redis'

# Optimize Redis connection for production memory constraints
redis_config = {
  url: ENV['REDIS_URL'] || (ENV['RAILS_ENV'] == 'production' ? ENV['REDIS_URL'] : 'redis://localhost:6379/0'),
  timeout: 1,
  reconnect_attempts: 1,
  reconnect_delay: 0.5,
  reconnect_delay_max: 1.0
}

# Create a single Redis connection instance instead of multiple
Rails.application.config.after_initialize do
  if defined?(REDIS)
    REDIS.redis.disconnect!
  end
  
  redis_instance = Redis.new(redis_config)
  
  # Set the global constant only once
  Object.const_set('REDIS', Redis::Namespace.new('MD_backend', redis: redis_instance)) unless defined?(REDIS)
  
  Rails.logger.info("Redis connection established: #{redis_instance.id}")
end

# Optimize memory by ensuring connections are closed properly
at_exit do
  if defined?(REDIS)
    REDIS.redis.disconnect!
    Rails.logger.info("Redis connection closed on exit")
  end
end

def store_last_location(user_id, location_data)
  REDIS.set("user:#{user_id}:last_location", location_data.to_json)
rescue Redis::BaseError => e
  Rails.logger.error("Redis error in store_last_location: #{e.message}")
end

def get_last_location(user_id)
  location_json = REDIS.get("user:#{user_id}:last_location")
  location_json ? JSON.parse(location_json) : nil
rescue Redis::BaseError => e
  Rails.logger.error("Redis error in get_last_location: #{e.message}")
  nil
end
