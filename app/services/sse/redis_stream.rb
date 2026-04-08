require "securerandom"
require "timeout"

module Sse
  class RedisStream
    PING_INTERVAL_SECONDS = Integer(ENV.fetch("SSE_PING_INTERVAL_SECONDS", 12))
    QUEUE_POP_TIMEOUT_SECONDS = 1
    # Hard cap on how long one SSE request may hold a Puma thread. When the browser tab is gone but TCP is
    # half-open, Rack may not call body.close (stream.abort) for many minutes (~15–30m is common). Forcing a
    # graceful server-side end lets EventSource reconnect quickly. Set to 0 to disable (not recommended).
    MAX_STREAM_SECONDS = Integer(ENV.fetch("SSE_MAX_STREAM_SECONDS", 480))

    attr_reader :stream_id

    def initialize(response:, channel:, user_id:, kind:, ping_interval_seconds: PING_INTERVAL_SECONDS)
      @response = response
      @channel = channel
      @user_id = user_id
      @kind = kind
      @ping_interval_seconds = ping_interval_seconds
      @stream_id = SecureRandom.uuid
      @closing = false
      @close_reason = nil
      @mutex = Mutex.new
      @queue = Queue.new
    end

    def run
      @stream_started_monotonic = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      register_stream!
      write_initial_comment!
      start_subscriber!
      write_loop!
    rescue IOError, ActionController::Live::ClientDisconnected => e
      close!("client_disconnect", error: e)
    rescue StandardError => e
      close!("error", error: e)
      raise
    ensure
      close!("ensure")
      ActiveRecord::Base.connection_handler.clear_active_connections!
    end

    def close!(reason = "manual_close", error: nil)
      already_closed = nil

      @mutex.synchronize do
        already_closed = @closing
        unless @closing
          @closing = true
          @close_reason = reason
        end
      end

      return if already_closed

      unsubscribe_redis!
      close_redis!
      close_response_stream!
      join_subscriber!
      active_count = Sse::Registry.deregister(@stream_id)
      Rails.logger.info(
        "[sse] close stream_id=#{@stream_id} user_id=#{@user_id} kind=#{@kind} reason=#{@close_reason} " \
        "active=#{active_count} err=#{error&.class}"
      )
    end

    private

    def register_stream!
      evicted, active_count = Sse::Registry.register(
        stream_id: @stream_id,
        user_id: @user_id,
        kind: @kind
      ) { close!("evicted") }

      Rails.logger.info(
        "[sse] open stream_id=#{@stream_id} user_id=#{@user_id} kind=#{@kind} channel=#{@channel} active=#{active_count}"
      )

      return unless evicted

      Rails.logger.warn(
        "[sse] evict_oldest stream_id=#{evicted.stream_id} user_id=#{evicted.user_id} " \
        "kind=#{evicted.kind} reason=max_streams max=#{Sse::Registry::MAX_STREAMS}"
      )
      safely_call_evicted(evicted)
    end

    def safely_call_evicted(evicted)
      evicted.close_proc.call
    rescue StandardError => e
      Rails.logger.error("[sse] evict_failed stream_id=#{evicted.stream_id} err=#{e.class} #{e.message}")
    end

    def write_initial_comment!
      @response.stream.write(": connected stream_id=#{@stream_id}\n\n")
    end

    def start_subscriber!
      @redis = build_redis_client
      @subscriber_thread = Thread.new do
        Thread.current.abort_on_exception = false
        @redis.subscribe(@channel) do |on|
          on.message do |_ch, msg|
            @queue << msg unless closing?
          end
        end
      end
    end

    def write_loop!
      next_ping_at = Process.clock_gettime(Process::CLOCK_MONOTONIC) + @ping_interval_seconds
      max_deadline =
        if MAX_STREAM_SECONDS.positive?
          @stream_started_monotonic + MAX_STREAM_SECONDS
        end

      until closing?
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        if max_deadline && now >= max_deadline
          Rails.logger.info(
            "[sse] max_duration stream_id=#{@stream_id} user_id=#{@user_id} kind=#{@kind} " \
            "seconds=#{MAX_STREAM_SECONDS} (client should reconnect)"
          )
          close!("max_duration")
          break
        end

        msg = pop_queue
        write_payload!(msg) if msg

        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        if now >= next_ping_at
          write_ping!
          next_ping_at = now + @ping_interval_seconds
        end
      end
    end

    def pop_queue
      Timeout.timeout(QUEUE_POP_TIMEOUT_SECONDS) { @queue.pop }
    rescue Timeout::Error
      nil
    end

    def write_payload!(msg)
      @response.stream.write("data: #{msg}\n\n")
    end

    def write_ping!
      @response.stream.write(": ping #{Time.current.to_i}\n\n")
    end

    def unsubscribe_redis!
      return unless @redis

      @redis.unsubscribe(@channel)
    rescue StandardError
      nil
    end

    def close_redis!
      return unless @redis

      @redis.quit
    rescue StandardError
      nil
    ensure
      @redis = nil
    end

    def close_response_stream!
      @response.stream.close
    rescue StandardError
      nil
    end

    def join_subscriber!
      return unless @subscriber_thread

      @subscriber_thread.join(1.0)
    rescue StandardError
      nil
    ensure
      @subscriber_thread = nil
    end

    def build_redis_client
      if Rails.env.production?
        Redis.new(url: ENV["REDIS_URL"])
      else
        Redis.new(url: "redis://localhost:6379/0")
      end
    end

    def closing?
      @mutex.synchronize { @closing }
    end
  end
end
