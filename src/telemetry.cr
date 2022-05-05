require "defined"

# This allows opt-out of specific instrumentation at compile time, via environment variables.
# Refer to https://wyhaines.github.io/defined.cr/ for details about all supported check types.
unless_enabled?("OTEL_CRYSTAL_DISABLE_INSTRUMENTATION_RETHINKDB") do
  if_defined?(OpenTelemetry::Instrumentation::Instrument) do
    module OpenTelemetry::Instrumentation
      class RethinkDB < OpenTelemetry::Instrumentation::Instrument
      end
    end

    module RethinkDB
      class Connection
        trace("connect") do
          OpenTelemetry.trace.in_span("RethinkDB Connect") do |span|
            span["user"] = user
            span["db"] = db
            span["host"] = host
            span["port"] = port
            previous_def
          end
        end

        trace("authorise") do
          OpenTelemetry.trace.in_span("RethinkDB Authorise") do |span|
            span["user"] = user
            span["db"] = db
            span["host"] = host
            span["port"] = port
            previous_def
          end
        end

        class ResponseStream
          trace("query_term") do
            OpenTelemetry.trace.in_span("RethinkDB Query") do
              span["user"] = @conn.user
              span["db"] = @conn.db
              span["host"] = @conn.host
              span["port"] = @conn.port
              previous_def
            end
          end

          trace("query_continue") do
            OpenTelemetry.trace.in_span("RethinkDB Query Continue") do |span|
              span["user"] = @conn.user
              span["db"] = @conn.db
              span["host"] = @conn.host
              span["port"] = @conn.port
              previous_def
            end
          end
        end
      end
    end
  end
end
