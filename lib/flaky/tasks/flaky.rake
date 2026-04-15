# frozen_string_literal: true

# All tasks use environment variables instead of rake arguments
# to avoid zsh bracket escaping issues.
#
#   bin/rails flaky:fetch DURATION=28d
#   bin/rails flaky:rank SINCE=7
#   bin/rails flaky:history SPEC=path/to/spec.rb:42
#   bin/rails flaky:stress SPEC=path/to/spec.rb:42 N=20 SEED=12345 CI=true
#   bin/rails flaky:report

namespace :flaky do
  desc "Fetch recent CI results (DURATION=24h)"
  task fetch: :environment do
    require "flaky/commands/fetch"
    duration = ENV.fetch("DURATION", "24h")
    Flaky::Commands::Fetch.new(age: duration).execute
  end

  desc "Rank flaky tests by failure frequency (SINCE=30)"
  task rank: :environment do
    require "flaky/commands/rank"
    since = ENV.fetch("SINCE", "30").to_i
    Flaky::Commands::Rank.new(since_days: since).execute
  end

  desc "Show failure history for a spec (SPEC=path/to/spec.rb:42)"
  task history: :environment do
    require "flaky/commands/history"
    spec = ENV["SPEC"] || abort("Usage: bin/rails flaky:history SPEC=path/to/spec.rb:42")
    Flaky::Commands::History.new(spec_location: spec).execute
  end

  desc "Stress test a spec (SPEC=... N=20 SEED=12345 CI=true)"
  task stress: :environment do
    require "flaky/commands/stress"
    spec = ENV["SPEC"] || abort("Usage: bin/rails flaky:stress SPEC=path/to/spec.rb:42")
    Flaky::Commands::Stress.new(
      spec_location: spec,
      iterations: ENV.fetch("N", "20").to_i,
      seed: ENV["SEED"]&.to_i,
      ci_simulate: ENV["CI"] == "true"
    ).execute
  end

  desc "Summary dashboard of flaky test status"
  task report: :environment do
    require "flaky/commands/report"
    Flaky::Commands::Report.new.execute
  end
end
