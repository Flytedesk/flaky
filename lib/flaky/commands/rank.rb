# frozen_string_literal: true

require_relative "../database"

module Flaky
  module Commands
    class Rank
      def initialize(since_days: 30, min_failures: 1)
        @since_days = since_days
        @min_failures = min_failures
        @db = Database.new
      end

      def execute
        conn = @db.connection
        branch = Flaky.configuration.branch

        rows = conn.execute(<<~SQL, [branch, "-#{@since_days} days", @min_failures])
          SELECT
            tf.spec_file,
            tf.line_number,
            tf.description,
            COUNT(*) as failure_count,
            MAX(tf.failed_at) as last_failure,
            GROUP_CONCAT(DISTINCT tf.seed) as seeds
          FROM test_failures tf
          JOIN ci_runs cr ON cr.workflow_id = tf.workflow_id
          WHERE cr.branch = ?
            AND cr.created_at >= datetime('now', ?)
          GROUP BY tf.spec_file, tf.line_number
          HAVING COUNT(*) >= ?
          ORDER BY failure_count DESC, last_failure DESC
        SQL

        if rows.empty?
          puts "No flaky tests found in the last #{@since_days} days."
          return
        end

        total_runs = conn.get_first_value(
          "SELECT COUNT(DISTINCT workflow_id) FROM ci_runs WHERE branch = ? AND created_at >= datetime('now', ?)",
          [branch, "-#{@since_days} days"]
        ).to_i

        puts "Flaky tests on #{branch} (last #{@since_days} days, #{total_runs} CI runs):\n\n"
        puts format("%-6s %-50s %s", "Fails", "Location", "Last Failure")
        puts "-" * 90

        rows.each_with_index do |row, i|
          location = "#{row['spec_file']}:#{row['line_number']}"
          truncated = location.length > 48 ? "...#{location[-45..]}" : location
          puts format("%-6d %-50s %s", row["failure_count"], truncated, row["last_failure"])

          if i == 0
            puts "\n  \e[33m▶ Next to investigate:\e[0m #{location}"
            puts "    #{row['description']}"
            puts "    Seeds: #{row['seeds']}"
            puts ""
          end
        end
      ensure
        @db.close
      end
    end
  end
end
