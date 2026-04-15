# frozen_string_literal: true

require_relative "../repository"

module Flaky
  module Commands
    class Report
      def initialize
        @repo = Repository.new
      end

      def execute
        branch = Flaky.configuration.branch
        stats = @repo.run_stats(branch: branch)
        trend = @repo.failure_trend(branch: branch)

        puts "=== Flaky Test Report (#{branch}) ==="
        puts ""
        puts "CI Runs tracked:     #{stats[:total_runs]}"
        failure_pct = stats[:total_runs] > 0 ? (stats[:failed_runs].to_f / stats[:total_runs] * 100).round(1) : 0
        puts "Failed runs:         #{stats[:failed_runs]} (#{failure_pct}%)"
        puts "Total test failures: #{stats[:total_failures]}"
        puts "Unique flaky specs:  #{stats[:unique_specs]}"
        puts "Last fetch:          #{stats[:last_fetch] || 'never'}"

        puts ""
        puts "7-day trend:         #{trend[:recent]} failures (prior 7 days: #{trend[:prior]})"

        if trend[:recent] > trend[:prior]
          puts "                     \e[31m▲ Trending worse\e[0m"
        elsif trend[:recent] < trend[:prior]
          puts "                     \e[32m▼ Trending better\e[0m"
        else
          puts "                     → Stable"
        end

        top = @repo.top_flaky(branch: branch)
        if top.any?
          puts "\nTop 5 flaky tests:"
          puts "-" * 80
          top.each_with_index do |row, i|
            puts "  #{i + 1}. #{row['spec_file']}:#{row['line_number']} (#{row['failure_count']}x)"
            puts "     #{row['description']}"
          end
        end

        stress = @repo.recent_stress_runs
        if stress.any?
          puts "\nRecent stress runs:"
          puts "-" * 80
          stress.each do |run|
            total = run["passes"] + run["failures"]
            rate = total > 0 ? (run["failures"].to_f / total * 100).round(1) : 0
            ci_flag = run["ci_simulation"] == 1 ? " [CI sim]" : ""
            puts "  #{run['spec_location']} — #{run['passes']}/#{total} passed (#{rate}% failure rate)#{ci_flag}"
          end
        end
      ensure
        @repo.close
      end
    end
  end
end
