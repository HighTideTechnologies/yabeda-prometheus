# frozen_string_literal: true

require "prometheus/middleware/exporter"
require "rack"

module Yabeda
  module Prometheus
    # Rack application or middleware that provides metrics exposition endpoint
    class Exporter < ::Prometheus::Middleware::Exporter
      NOT_FOUND_HANDLER = lambda do |_env|
        [404, { "Content-Type" => "text/plain" }, ["Not Found\n"]]
      end.freeze

      class << self
        # Allows to use middleware as standalone rack application
        def call(env)
          @app ||= new(NOT_FOUND_HANDLER, path: "/")
          @app.call(env)
        end

        def start_metrics_server!
          pp 'before Thread #start_metrics_server!'
          Thread.new do
            begin
              default_port = ENV.fetch("PORT", 9394)
              pp 'before #start_metrics_server! #run'
              ::Rack::Handler::WEBrick.run(
                rack_app,
                Host: ENV["PROMETHEUS_EXPORTER_BIND"] || "0.0.0.0",
                Port: ENV.fetch("PROMETHEUS_EXPORTER_PORT", default_port),
                AccessLog: [],
              )
              pp 'after #start_metrics_server! #run'
            rescue StandardError =>  error
              pp "RESCUE IN #start_metrics_server! ~ StandardError: ", error
            end
          end
        end

        def rack_app(exporter = self, path: "/metrics")
          begin
          ::Rack::Builder.new do
            use ::Rack::CommonLogger
            use ::Rack::ShowExceptions
            use exporter, path: path
            run NOT_FOUND_HANDLER
          end
          rescue StandardError =>  error
            pp "RESCUE IN #rack_app ~ StandardError: ", error
          end
        end
      end

      def initialize(app, options = {})
        super(app, options.merge(registry: Yabeda::Prometheus.registry))
      end

      def call(env)
        ::Yabeda.collect! if env["PATH_INFO"] == path

        if ::Yabeda.debug?
          result = nil
          ::Yabeda.prometheus_exporter.render_duration.measure({}) do
            result = super
          end
          result
        else
          super
        end
      end
    end
  end
end
