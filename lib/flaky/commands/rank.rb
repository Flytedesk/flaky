# frozen_string_literal: true

require_relative "../repository"

module Flaky
  module Commands
    class Rank
      def initialize(since_days: 30, min_failures: 1)
        @since_days = since_days
        @min_failures = min_failures
        @repo = Repository.new
      end

      def execute
        branch = Flaky.configuration.branch

        rows = @repo.rank_failures(branch: branch, since_days: @since_days, min_failures: @min_failures)

        if rows.empty?
          puts "No flaky tests found in the last #{@since_days} days."
          return
        end

        total_runs = @repo.total_runs_count(branch: branch, since_days: @since_days)

        puts "Flaky tests on #{branch} (last #{@since_days} days, #{total_runs} CI runs):\n\n"
        puts format("%-6s %s", "Fails", "Location")
        puts "-" * 90

        rows.each_with_index do |row, i|
          location = "#{row['spec_file']}:#{row['line_number']}"
          puts format("%-6d %s  (%s)", row["failure_count"], location, row["last_failure"])

          if i == 0
            puts "\n  \e[33m▶ Next to investigate:\e[0m #{location}"
            puts "    #{row['description']}"
            puts "    Seeds: #{row['seeds']}"
            puts "    Commits: #{row['commit_shas']}" if row["commit_shas"]
            puts ""
          end
        end
      ensure
        @repo.close
      end
    end
  end
end
