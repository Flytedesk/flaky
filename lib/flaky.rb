# frozen_string_literal: true

require_relative "flaky/version"
require_relative "flaky/configuration"
require_relative "flaky/providers/semaphore"
require_relative "flaky/providers/github_actions"
require_relative "flaky/railtie" if defined?(Rails::Railtie)

module Flaky
  class Error < StandardError; end

  class << self
    def configuration
      @configuration ||= Configuration.new
    end

    def configure
      yield(configuration)
    end

    def provider
      configuration.provider_instance
    end

    def register_provider(name, klass)
      Configuration.register_provider(name, klass)
    end
  end
end
