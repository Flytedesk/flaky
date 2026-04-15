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

        print "Fetching #{branch} workflows (last #{@age})... "
        $stdout.flush
        workflows = provider.fetch_workflows(age: @age)
        puts "#{workflows.length} found."

        if workflows.empty?
          puts "Nothing to do."
          return
        end

        # Filter out already-fetched workflows
        new_workflows = workflows.reject do |wf|
          conn.get_first_value("SELECT 1 FROM ci_runs WHERE workflow_id = ?", wf[:id])
        end

        if new_workflows.empty?
          puts "All #{workflows.length} workflows already in database."
          return
        end

        puts "Processing #{new_workflows.length} new workflow(s)..."

        total_jobs = 0
        total_failures = 0

        new_workflows.each_with_index do |wf, wi|
          print "  [#{wi + 1}/#{new_workflows.length}] #{wf[:created_at]} — fetching jobs... "
          $stdout.flush

          jobs = provider.fetch_jobs(pipeline_id: wf[:pipeline_id])
          pipeline_result = jobs.any? { |j| j[:result] == "failed" } ? "failed" : "passed"

          conn.execute(
            "INSERT INTO ci_runs (workflow_id, pipeline_id, branch, result, created_at) VALUES (?, ?, ?, ?, ?)",
            [wf[:id], wf[:pipeline_id], wf[:branch], pipeline_result, wf[:created_at]]
          )

          puts "#{jobs.length} test jobs (#{pipeline_result})"

          jobs.each_with_index do |job, ji|
            print "    [#{ji + 1}/#{jobs.length}] #{job[:name]}... "
            $stdout.flush

            log = provider.fetch_log(job_id: job[:id])
            parsed = @parser.parse(log)
            total_jobs += 1

            job_result = parsed.failure_count.to_i > 0 ? "failed" : "passed"

            conn.execute(
              "INSERT OR IGNORE INTO job_results (job_id, workflow_id, job_name, block_name, result, example_count, failure_count, seed, duration_seconds) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
              [job[:id], wf[:id], job[:name], job[:block_name], job_result,
               parsed.example_count, parsed.failure_count, parsed.seed, parsed.duration_seconds]
            )

            if parsed.failures.any?
              parsed.failures.each do |failure|
                conn.execute(
                  "INSERT OR IGNORE INTO test_failures (workflow_id, job_id, job_name, spec_file, line_number, description, seed, branch, failed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
                  [wf[:id], job[:id], job[:name], failure.spec_file, failure.line_number, failure.description,
                   parsed.seed, wf[:branch], wf[:created_at]]
                )
                total_failures += 1
              end
              puts "\e[31m#{parsed.failures.length} failure(s)\e[0m"
            else
              puts "\e[32mok\e[0m (#{parsed.example_count} examples)"
            end
          end
        end

        puts "\nDone: #{new_workflows.length} workflow(s), #{total_jobs} job(s), #{total_failures} failure(s) recorded."
      ensure
        @db.close
      end
    end
  end
end
