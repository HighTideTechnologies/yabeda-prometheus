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
          Thread.new do
            begin
              default_port = ENV.fetch("PORT", 9394)
              ::Rack::Handler::WEBrick.run(
                rack_app,
                Host: ENV["PROMETHEUS_EXPORTER_BIND"] || "0.0.0.0",
                Port: ENV.fetch("PROMETHEUS_EXPORTER_PORT", default_port),
                AccessLog: [],
              )
            rescue StandardError =>  error
              pp "#start_metrics_server! StandardError: ", error
            end
          end
        end

        def rack_app(exporter = self, path: "/metrics")
          begin
          pp 'inside #rack_app'
          ::Rack::Builder.new do
            use ::Rack::CommonLogger
            pp 'after CommonLogger'
            
            use ::Rack::ShowExceptions
            pp 'after ShowExceptions'
            
            use exporter, path: path
            pp 'after exporter'
            
            run NOT_FOUND_HANDLER
            pp 'after run'
          end
          rescue StandardError =>  error
            pp "#rack_app StandardError: ", error
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
