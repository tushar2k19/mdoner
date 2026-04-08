module Sse
  class Registry
    Entry = Struct.new(:stream_id, :user_id, :kind, :started_at, :close_proc, keyword_init: true)

    MAX_STREAMS = Integer(ENV.fetch("SSE_MAX_STREAMS", 3))

    @mutex = Mutex.new
    @entries = {}

    class << self
      def register(stream_id:, user_id:, kind:, &close_proc)
        raise ArgumentError, "close proc required" unless block_given?

        evicted = nil
        active_count = nil

        @mutex.synchronize do
          @entries[stream_id] = Entry.new(
            stream_id: stream_id,
            user_id: user_id,
            kind: kind,
            started_at: Time.current,
            close_proc: close_proc
          )

          if @entries.size > MAX_STREAMS
            oldest = @entries.values.min_by(&:started_at)
            if oldest && oldest.stream_id != stream_id
              evicted = oldest
              @entries.delete(oldest.stream_id)
            end
          end

          active_count = @entries.size
        end

        [evicted, active_count]
      end

      def deregister(stream_id)
        @mutex.synchronize do
          @entries.delete(stream_id)
          @entries.size
        end
      end

      def active_count
        @mutex.synchronize { @entries.size }
      end
    end
  end
end
