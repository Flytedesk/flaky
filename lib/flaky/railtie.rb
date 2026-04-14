# frozen_string_literal: true

module Flaky
  class Railtie < Rails::Railtie
    rake_tasks do
      load File.expand_path("tasks/flaky.rake", __dir__)
    end

    initializer "flaky.middleware" do |app|
      if ENV["FLAKY_CI_SIMULATE"] && Rails.env.test?
        require_relative "middleware/simulate_ci_latency"
        app.middleware.use Flaky::Middleware::SimulateCiLatency
      end
    end
  end
end
