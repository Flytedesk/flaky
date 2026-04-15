# frozen_string_literal: true

module Flaky
  class Configuration
    PROVIDERS = {}

    attr_accessor :project, :branch, :db_path, :test_blocks

    def initialize
      @provider_name = nil
      @project = nil
      @branch = "main"
      @db_path = nil # resolved lazily
      @test_blocks = ["Unit Tests", "System Tests"]
    end

    def provider=(name)
      @provider_name = name.to_sym
    end

    def provider_instance
      validate!
      klass = PROVIDERS[@provider_name] || raise(Error, "Unknown provider: #{@provider_name}. Registered: #{PROVIDERS.keys.join(', ')}")
      klass.new(self)
    end

    def resolved_db_path
      @db_path || (defined?(Rails) ? Rails.root.join("tmp", "flaky.db").to_s : "tmp/flaky.db")
    end

    def validate!
      unless @provider_name
        raise Error, "Flaky: provider not configured. Add `Flaky.configure { |c| c.provider = :semaphore }` to your initializer."
      end
      unless @project
        raise Error, "Flaky: project not configured. Add `Flaky.configure { |c| c.project = 'your-project' }` to your initializer."
      end
    end

    def self.register_provider(name, klass)
      PROVIDERS[name.to_sym] = klass
    end
  end
end
