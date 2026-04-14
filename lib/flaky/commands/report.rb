# frozen_string_literal: true

require_relative "../database"

module Flaky
  module Commands
    class Report
      def initialize
        @db = Database.new
      end

      def execute
        conn = @db.connection
        branch = Flaky.configuration.branch

        total_runs = conn.get_first_value("SELECT COUNT(*) FROM ci_runs WHERE branch = ?", branch).to_i
        failed_runs = conn.get_first_value("SELECT COUNT(*) FROM ci_runs WHERE branch = ? AND result = 'failed'", branch).to_i
        total_failures = conn.get_first_value("SELECT COUNT(*) FROM test_failures WHERE branch = ?", branch).to_i
        unique_specs = conn.get_first_value("SELECT COUNT(DISTINCT spec_file || ':' || line_number) FROM test_failures WHERE branch = ?", branch).to_i
        last_fetch = conn.get_first_value("SELECT MAX(fetched_at) FROM ci_runs")

        puts "=== Flaky Test Report (#{branch}) ==="
        puts ""
        puts "CI Runs tracked:     #{total_runs}"
        puts "Failed runs:         #{failed_runs} (#{total_runs > 0 ? (failed_runs.to_f / total_runs * 100).round(1) : 0}%)"
        puts "Total test failures: #{total_failures}"
        puts "Unique flaky specs:  #{unique_specs}"
        puts "Last fetch:          #{last_fetch || 'never'}"

        # Recent trend
        recent = conn.get_first_value(
          "SELECT COUNT(*) FROM test_failures WHERE branch = ? AND failed_at >= datetime('now', '-7 days')", branch
        ).to_i
        prior = conn.get_first_value(
          "SELECT COUNT(*) FROM test_failures WHERE branch = ? AND failed_at >= datetime('now', '-14 days') AND failed_at < datetime('now', '-7 days')", branch
        ).to_i

        puts ""
        puts "7-day trend:         #{recent} failures (prior 7 days: #{prior})"

        if recent > prior
          puts "                     \e[31m▲ Trending worse\e[0m"
        elsif recent < prior
          puts "                     \e[32m▼ Trending better\e[0m"
        else
          puts "                     → Stable"
        end

        # Top 5 flaky tests
        top = conn.execute(<<~SQL, [branch])
          SELECT
            spec_file,
            line_number,
            description,
            COUNT(*) as failure_count,
            MAX(failed_at) as last_failure
          FROM test_failures
          WHERE branch = ?
          GROUP BY spec_file, line_number
          ORDER BY failure_count DESC
          LIMIT 5
        SQL

        if top.any?
          puts "\nTop 5 flaky tests:"
          puts "-" * 80
          top.each_with_index do |row, i|
            puts "  #{i + 1}. #{row['spec_file']}:#{row['line_number']} (#{row['failure_count']}x)"
            puts "     #{row['description']}"
          end
        end

        # Recent stress runs
        stress = conn.execute("SELECT * FROM stress_runs ORDER BY created_at DESC LIMIT 3")
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
        @db.close
      end
    end
  end
end
