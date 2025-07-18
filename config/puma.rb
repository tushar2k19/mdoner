# This configuration file will be evaluated by Puma. The top-level methods that
# are invoked here are part of Puma's configuration DSL. For more information
# about methods provided by the DSL, see https://puma.io/puma/Puma/DSL.html.

# Puma can serve each request in a thread from an internal thread pool.
# The `threads` method setting takes two numbers: a minimum and maximum.
# Any libraries that use thread pools should be configured to match
# the maximum value specified for Puma. Default is set to 5 threads for minimum
# and maximum; this matches the default thread size of Active Record.
max_threads_count = ENV.fetch("RAILS_MAX_THREADS") { 5 } #5
min_threads_count = ENV.fetch("RAILS_MIN_THREADS") { 2 } #max_threads_count  
threads min_threads_count, max_threads_count

# Limit workers for small applications to save memory
if ENV["RAILS_ENV"] == "production"
  require "concurrent-ruby"
  
  # For testing/small applications, use just 1 worker to minimize memory usage
  # This saves maximum memory while still providing thread-based concurrency
  max_workers = 2  # Single worker for testing - saves most memory
  
  worker_count = Integer(ENV.fetch("WEB_CONCURRENCY") { Concurrent.physical_processor_count })
  # Cap the worker count to our maximum
  worker_count = [worker_count, max_workers].min
  
  workers worker_count if worker_count > 1
end

# Specifies the `worker_timeout` threshold that Puma will use to wait before
# terminating a worker in development environments.
worker_timeout 3600 if ENV.fetch("RAILS_ENV", "development") == "development"

# Specifies the `port` that Puma will listen on to receive requests; default is 3000.
port ENV.fetch("PORT") { 3000 }

# Specifies the `environment` that Puma will run in.
environment ENV.fetch("RAILS_ENV") { "development" }

# Specifies the `pidfile` that Puma will use.
pidfile ENV.fetch("PIDFILE") { "tmp/pids/server.pid" }

# Allow puma to be restarted by `bin/rails restart` command.
plugin :tmp_restart
