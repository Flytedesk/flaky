# frozen_string_literal: true

module Flaky
  class Configuration
    PROVIDERS = {}

    attr_accessor :project, :branch, :db_path

    def initialize
      @provider_name = nil
      @project = nil
      @branch = "main"
      @db_path = nil # resolved lazily
    end

    def provider=(name)
      @provider_name = name.to_sym
    end

    def provider_instance
      klass = PROVIDERS[@provider_name] || raise(Error, "Unknown provider: #{@provider_name}. Registered: #{PROVIDERS.keys.join(', ')}")
      klass.new(self)
    end

    def resolved_db_path
      @db_path || (defined?(Rails) ? Rails.root.join("tmp", "flaky.db").to_s : "tmp/flaky.db")
    end

    def self.register_provider(name, klass)
      PROVIDERS[name.to_sym] = klass
    end
  end
end
