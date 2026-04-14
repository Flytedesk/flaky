# frozen_string_literal: true

require_relative "../database"

module Flaky
  module Commands
    class History
      def initialize(spec_location:)
        @spec_location = spec_location
        @db = Database.new
      end

      def execute
        conn = @db.connection

        file, line = parse_location(@spec_location)

        conditions = ["tf.spec_file LIKE ?"]
        params = ["%#{file}%"]

        if line
          conditions << "tf.line_number = ?"
          params << line
        end

        rows = conn.execute(<<~SQL, params)
          SELECT
            tf.spec_file,
            tf.line_number,
            tf.description,
            tf.seed,
            tf.job_name,
            tf.branch,
            tf.failed_at,
            cr.workflow_id
          FROM test_failures tf
          JOIN ci_runs cr ON cr.workflow_id = tf.workflow_id
          WHERE #{conditions.join(" AND ")}
          ORDER BY tf.failed_at DESC
        SQL

        if rows.empty?
          puts "No failures found matching '#{@spec_location}'."
          return
        end

        first = rows.first
        puts "Failure history for #{first['spec_file']}:#{first['line_number']}"
        puts "  #{first['description']}\n\n"
        puts format("%-20s %-8s %-30s %s", "Date", "Seed", "Job", "Workflow")
        puts "-" * 100

        rows.each do |row|
          puts format("%-20s %-8d %-30s %s", row["failed_at"], row["seed"], row["job_name"], row["workflow_id"])
        end

        puts "\nTotal failures: #{rows.length}"

        seeds = rows.map { |r| r["seed"] }.uniq
        puts "Unique seeds: #{seeds.join(', ')}"
        puts "\nTo reproduce: rake flaky:stress[#{first['spec_file']}:#{first['line_number']},10,#{seeds.first},true]"
      ensure
        @db.close
      end

      private

      def parse_location(loc)
        if loc.include?(":")
          parts = loc.rpartition(":")
          [parts[0], parts[2].to_i]
        else
          [loc, nil]
        end
      end
    end
  end
end
