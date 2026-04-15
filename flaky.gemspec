# frozen_string_literal: true

require_relative "lib/flaky/version"

Gem::Specification.new do |spec|
  spec.name = "flaky-friend"
  spec.version = Flaky::VERSION
  spec.authors = ["Flytedesk"]
  spec.summary = "Track, rank, and reproduce flaky CI test failures"
  spec.description = "Fetches CI test results, stores failures in SQLite, ranks by frequency, and reproduces under simulated CI conditions."
  spec.homepage = "https://github.com/Flytedesk/flaky"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir["lib/**/*", "LICENSE", "README.md"]
  spec.require_paths = ["lib"]

  spec.add_dependency "sqlite3", "~> 2.0"
  spec.add_dependency "railties", ">= 7.0"

  spec.add_development_dependency "rake", "~> 13.0"
  spec.add_development_dependency "rspec", "~> 3.0"
end
