# frozen_string_literal: true

require_relative "../database"
require_relative "../log_parser"

module Flaky
  module Commands
    class Fetch
      def initialize(age: "24h")
        @age = age
        @db = Database.new
        @parser = LogParser.new
      end

      def execute
        provider = Flaky.provider
        branch = Flaky.configuration.branch
        conn = @db.connection

        workflows = provider.fetch_workflows(age: @age)
        main_workflows = workflows.select { |w| w[:branch] == branch }

        if main_workflows.empty?
          puts "No #{branch} workflows found in the last #{@age}."
          return
        end

        new_workflows = 0
        new_failures = 0
        total_jobs = 0

        main_workflows.each do |wf|
          # Skip if already fetched
          existing = conn.get_first_value("SELECT 1 FROM ci_runs WHERE workflow_id = ?", wf[:id])
          next if existing

          # Determine pipeline result by fetching jobs
          jobs = provider.fetch_jobs(pipeline_id: wf[:pipeline_id])
          pipeline_result = jobs.any? { |j| j[:result] == "failed" } ? "failed" : "passed"

          conn.execute(
            "INSERT INTO ci_runs (workflow_id, pipeline_id, branch, result, created_at) VALUES (?, ?, ?, ?, ?)",
            [wf[:id], wf[:pipeline_id], wf[:branch], pipeline_result, wf[:created_at]]
          )
          new_workflows += 1

          jobs.each do |job|
            total_jobs += 1
            log = provider.fetch_log(job_id: job[:id])
            parsed = @parser.parse(log)

            conn.execute(
              "INSERT OR IGNORE INTO job_results (job_id, workflow_id, job_name, block_name, result, example_count, failure_count, seed, duration_seconds) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
              [job[:id], wf[:id], job[:name], job[:block_name], parsed.failure_count.to_i > 0 ? "failed" : "passed",
               parsed.example_count, parsed.failure_count, parsed.seed, parsed.duration_seconds]
            )

            parsed.failures.each do |failure|
              conn.execute(
                "INSERT OR IGNORE INTO test_failures (workflow_id, job_id, job_name, spec_file, line_number, description, seed, branch, failed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                [wf[:id], job[:id], job[:name], failure.spec_file, failure.line_number, failure.description,
                 parsed.seed, wf[:branch], wf[:created_at]]
              )
              new_failures += 1
            end
          end
        end

        puts "Fetched #{new_workflows} new workflow(s), #{total_jobs} job(s) parsed, #{new_failures} failure(s) recorded."
      ensure
        @db.close
      end
    end
  end
end
