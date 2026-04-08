require 'redis'

# redis = Redis.new(url: ENV['REDIS_URL'] || 'redis://localhost:6379/0') if ENV['RAILS_ENV'] != 'production'
# redis = Redis.new(url: ENV['REDIS_URL'], password: ENV['REDIS_AUTH_TOKEN']) if ENV['RAILS_ENV'] == 'production'

# REDIS_PASSWORD = ENV['REDIS_PASSWORD'] || ''
# REDIS_HOST = ENV['REDIS_HOST']
# REDIS_PORT = ENV['REDIS_PORT']
# REDIS_URL = "rediss://:#{REDIS_PASSWORD}@#{REDIS_HOST}" 

if ENV['RAILS_ENV'] == 'production'
  redis = Redis.new(
    url: ENV['REDIS_URL']
  )
  Rails.logger.info("Using_Redis_URL: #{redis}")
else
  redis = Redis.new(url: 'redis://localhost:6379/0')
end
REDIS = Redis::Namespace.new('MD_backend', redis: redis)
Rails.logger.info("__REDIS_set_successfully__") if REDIS
Rails.logger.info(redis) if REDIS

# Pub/sub channel names used with a *plain* Redis client (e.g. per-request SSE subscribe)
# must match what Redis::Namespace adds on REDIS.publish (:first arg → "namespace:channel").
module RedisPubSubChannel
  module_function

  def namespaced_channel(channel_without_prefix)
    return channel_without_prefix if channel_without_prefix.blank?

    ns = REDIS.namespace
    ns = ns.call if ns.respond_to?(:call)
    ns.present? ? "#{ns}:#{channel_without_prefix}" : channel_without_prefix
  end
end

