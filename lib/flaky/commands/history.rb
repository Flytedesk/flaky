# frozen_string_literal: true

require_relative "../repository"

module Flaky
  module Commands
    class History
      def initialize(spec_location:)
        @spec_location = spec_location
        @repo = Repository.new
      end

      def execute
        file, line = parse_location(@spec_location)
        rows = @repo.failure_history(file: file, line: line)

        if rows.empty?
          puts "No failures found matching '#{@spec_location}'."
          return
        end

        first = rows.first
        puts "Failure history for #{first['spec_file']}:#{first['line_number']}"
        puts "  #{first['description']}\n\n"
        puts format("%-20s %-8s %-10s %-30s %s", "Date", "Seed", "Commit", "Job", "Workflow")
        puts "-" * 110

        rows.each do |row|
          sha = row["commit_sha"] ? row["commit_sha"][0..6] : "       "
          puts format("%-20s %-8d %-10s %-30s %s", row["failed_at"], row["seed"], sha, row["job_name"], row["workflow_id"])
        end

        puts "\nTotal failures: #{rows.length}"

        seeds = rows.map { |r| r["seed"] }.uniq
        puts "Unique seeds: #{seeds.join(', ')}"
        puts "\nTo reproduce: SPEC=#{first['spec_file']}:#{first['line_number']} SEED=#{seeds.first} CI=true bin/rails flaky:stress"
      ensure
        @repo.close
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
