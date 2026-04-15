# frozen_string_literal: true

# All tasks use environment variables instead of rake arguments
# to avoid zsh bracket escaping issues.
#
#   bin/rails flaky:fetch DURATION=28d
#   bin/rails flaky:rank SINCE=7
#   bin/rails flaky:history SPEC=path/to/spec.rb:42
#   bin/rails flaky:stress SPEC=path/to/spec.rb:42 N=20 SEED=12345 CI=true TIMEOUT=600
#   bin/rails flaky:report

FLAKY_HELP = <<~HELP
  \e[1mflaky-friend v#{Flaky::VERSION}\e[0m — Track, rank, and reproduce flaky CI test failures

  \e[1mUsage:\e[0m
    bin/rails flaky:<command> [ENV_VARS]

  \e[1mCommands:\e[0m
    flaky:fetch    Fetch recent CI results into the local database
    flaky:rank     Rank flaky tests by failure frequency
    flaky:history  Show failure history for a specific spec
    flaky:stress   Stress-test a spec to reproduce/prove a fix
    flaky:report   Summary dashboard of flaky test status

  \e[1mExamples:\e[0m
    bin/rails flaky:fetch                          # last 24 hours (default)
    bin/rails flaky:fetch DURATION=28d             # last 28 days
    bin/rails flaky:rank                           # last 30 days (default)
    bin/rails flaky:rank SINCE=7                   # last 7 days
    bin/rails flaky:history SPEC=spec/foo_spec.rb:42
    bin/rails flaky:stress SPEC=spec/foo_spec.rb:42 N=20 SEED=12345 CI=true
    bin/rails flaky:report

  \e[1mEnvironment variables:\e[0m
    DURATION   Age window for fetch (e.g. 24h, 7d, 30m)          [default: 24h]
    SINCE      Number of days to look back for rank               [default: 30]
    SPEC       Spec file location (path/to/spec.rb or path:line)
    N          Number of stress test iterations                   [default: 20]
    SEED       RSpec seed (omit=use known failing seeds, "random"=random)
    CI         Set to "true" to enable CI simulation (latency + reduced threads)
    TIMEOUT    Stress test timeout in seconds                     [default: 600]

HELP

desc "Show flaky-friend help"
task :flaky do
  puts FLAKY_HELP
end

namespace :flaky do
  desc "Show flaky-friend help"
  task help: :environment do
    puts FLAKY_HELP
  end

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

  desc "Stress test a spec (SPEC=... N=20 SEED=12345 CI=true TIMEOUT=600)"
  task stress: :environment do
    require "flaky/commands/stress"
    spec = ENV["SPEC"] || abort("Usage: bin/rails flaky:stress SPEC=path/to/spec.rb:42")
    seed = case ENV["SEED"]
           when nil then nil
           when "random" then :random
           else ENV["SEED"].to_i
           end
    Flaky::Commands::Stress.new(
      spec_location: spec,
      iterations: ENV.fetch("N", "20").to_i,
      seed: seed,
      ci_simulate: ENV["CI"] == "true",
      timeout: ENV.fetch("TIMEOUT", "600").to_i
    ).execute
  end

  desc "Summary dashboard of flaky test status"
  task report: :environment do
    require "flaky/commands/report"
    Flaky::Commands::Report.new.execute
  end
end
