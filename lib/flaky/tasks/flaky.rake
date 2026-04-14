# frozen_string_literal: true

namespace :flaky do
  desc "Fetch recent CI results (age: duration, default 24h)"
  task :fetch, [:age] => :environment do |_t, args|
    require "flaky/commands/fetch"
    age = args[:age] || "24h"
    Flaky::Commands::Fetch.new(age: age).execute
  end

  desc "Rank flaky tests by failure frequency (since: days, default 30)"
  task :rank, [:since] => :environment do |_t, args|
    require "flaky/commands/rank"
    since = (args[:since] || 30).to_i
    Flaky::Commands::Rank.new(since_days: since).execute
  end

  desc "Show failure history for a spec (spec_location: file:line)"
  task :history, [:spec_location] => :environment do |_t, args|
    require "flaky/commands/history"
    raise "Usage: rake flaky:history[path/to/spec.rb:42]" unless args[:spec_location]
    Flaky::Commands::History.new(spec_location: args[:spec_location]).execute
  end

  desc "Stress test a spec (spec, iterations, seed, ci)"
  task :stress, [:spec, :iterations, :seed, :ci] => :environment do |_t, args|
    require "flaky/commands/stress"
    raise "Usage: rake flaky:stress[path/to/spec.rb:42,20,12345,true]" unless args[:spec]
    Flaky::Commands::Stress.new(
      spec_location: args[:spec],
      iterations: (args[:iterations] || 20).to_i,
      seed: args[:seed]&.to_i,
      ci_simulate: args[:ci] == "true"
    ).execute
  end

  desc "Summary dashboard of flaky test status"
  task report: :environment do
    require "flaky/commands/report"
    Flaky::Commands::Report.new.execute
  end
end
