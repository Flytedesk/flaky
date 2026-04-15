# frozen_string_literal: true

require "json"
require_relative "base"
require_relative "../age_parser"

module Flaky
  module Providers
    class GithubActions < Base
      def fetch_workflows(age: "24h")
        cutoff = Time.now - AgeParser.to_seconds(age)

        output = run_cmd("gh run list --branch #{config.branch} --limit 100 --json databaseId,conclusion,createdAt,headBranch,headSha,workflowName")
        runs = JSON.parse(output)

        runs.filter_map do |run|
          created = Time.parse(run["createdAt"])
          next if created < cutoff

          {
            id: run["databaseId"].to_s,
            pipeline_id: run["databaseId"].to_s,
            branch: run["headBranch"],
            commit_sha: run["headSha"],
            result: map_conclusion(run["conclusion"]),
            created_at: run["createdAt"]
          }
        end
      end

      def fetch_jobs(pipeline_id:)
        output = run_cmd("gh run view #{pipeline_id} --json jobs")
        data = JSON.parse(output)

        (data["jobs"] || []).filter_map do |job|
          name = job["name"]
          next unless name.match?(/test/i)

          {
            id: job["databaseId"].to_s,
            name: name,
            block_name: name,
            result: map_conclusion(job["conclusion"])
          }
        end
      end

      def fetch_log(job_id:)
        run_cmd("gh run view --job #{job_id} --log")
      end

      private

      def run_cmd(cmd)
        output = `#{cmd} 2>/dev/null`
        raise Error, "Command failed (exit #{$?.exitstatus}): #{cmd}" unless $?.success?
        output
      end

      def map_conclusion(conclusion)
        case conclusion
        when "success" then "passed"
        when "failure" then "failed"
        else conclusion || "unknown"
        end
      end
    end

    Configuration.register_provider(:github_actions, GithubActions)
  end
end
