# frozen_string_literal: true

module Flaky
  module Middleware
    class SimulateCiLatency
      # f1-standard-2: 2 vCPU, 4 GB RAM (shared tenant)
      # Local Mac: 10+ cores, 16-64 GB RAM (dedicated)
      # Empirically, CI system tests take ~2x longer than local.
      # A 30ms delay per request approximates the difference.
      DEFAULT_DELAY_MS = 30

      def initialize(app, delay_ms: nil)
        @app = app
        @delay_ms = (delay_ms || ENV.fetch("FLAKY_LATENCY_MS", DEFAULT_DELAY_MS)).to_f
      end

      def call(env)
        sleep(@delay_ms / 1000.0) if @delay_ms > 0
        @app.call(env)
      end
    end
  end
end
