# frozen_string_literal: true

require_relative "../repository"
require_relative "../log_parser"

module Flaky
  module Commands
    class Fetch
      def initialize(age: "24h")
        @age = age
        @repo = Repository.new
        @parser = LogParser.new
      end

      def execute
        provider = Flaky.provider
        branch = Flaky.configuration.branch

        print "Fetching #{branch} workflows (last #{@age})... "
        $stdout.flush
        workflows = provider.fetch_workflows(age: @age)
        puts "#{workflows.length} found."

        if workflows.empty?
          puts "Nothing to do."
          return
        end

        new_workflows = workflows.reject { |wf| @repo.workflow_fetched?(wf[:id]) }

        if new_workflows.empty?
          puts "All #{workflows.length} workflows already in database."
          return
        end

        puts "Processing #{new_workflows.length} new workflow(s)..."

        total_jobs = 0
        total_failures = 0

        new_workflows.each_with_index do |wf, wi|
          jobs, failures = process_workflow(provider, wf, wi, new_workflows.length)
          total_jobs += jobs
          total_failures += failures
        end

        puts "\nDone: #{new_workflows.length} workflow(s), #{total_jobs} job(s), #{total_failures} failure(s) recorded."
      ensure
        @repo.close
      end

      private

      def process_workflow(provider, wf, index, total)
        print "  [#{index + 1}/#{total}] #{wf[:created_at]} — fetching jobs... "
        $stdout.flush

        jobs = provider.fetch_jobs(pipeline_id: wf[:pipeline_id])
        pipeline_result = jobs.any? { |j| j[:result] == "failed" } ? "failed" : "passed"

        @repo.insert_ci_run(
          workflow_id: wf[:id], pipeline_id: wf[:pipeline_id],
          branch: wf[:branch], result: pipeline_result, created_at: wf[:created_at]
        )

        puts "#{jobs.length} test jobs (#{pipeline_result})"

        failures = 0
        jobs.each_with_index do |job, ji|
          failures += process_job(provider, job, wf, ji, jobs.length)
        end

        [jobs.length, failures]
      end

      def process_job(provider, job, wf, index, total)
        print "    [#{index + 1}/#{total}] #{job[:name]}... "
        $stdout.flush

        log = provider.fetch_log(job_id: job[:id])
        parsed = @parser.parse(log)

        @repo.insert_job_result(
          job_id: job[:id], workflow_id: wf[:id], job_name: job[:name],
          block_name: job[:block_name], result: parsed.failure_count.to_i > 0 ? "failed" : "passed",
          example_count: parsed.example_count, failure_count: parsed.failure_count,
          seed: parsed.seed, duration_seconds: parsed.duration_seconds
        )

        if parsed.failures.any?
          parsed.failures.each do |failure|
            @repo.insert_test_failure(
              workflow_id: wf[:id], job_id: job[:id], job_name: job[:name],
              spec_file: failure.spec_file, line_number: failure.line_number,
              description: failure.description, seed: parsed.seed,
              branch: wf[:branch], failed_at: wf[:created_at]
            )
          end
          puts "\e[31m#{parsed.failures.length} failure(s)\e[0m"
          parsed.failures.length
        else
          puts "\e[32mok\e[0m (#{parsed.example_count} examples)"
          0
        end
      end
    end
  end
end
