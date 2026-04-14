# frozen_string_literal: true

require "yaml"
require_relative "base"

module Flaky
  module Providers
    class Semaphore < Base
      TEST_BLOCKS = ["Unit Tests", "System Tests"].freeze

      def fetch_workflows(age: "24h")
        output = run_cmd("sem get workflows -p #{config.project} --age #{age}")
        lines = output.lines.drop(1) # skip header
        lines.filter_map { |line| parse_workflow_line(line) }
      end

      def fetch_jobs(pipeline_id:)
        output = run_cmd("sem get pipelines #{pipeline_id}")
        data = YAML.safe_load(output, permitted_classes: [Date, Time])
        blocks = data&.[]("blocks")
        return [] unless blocks

        blocks.flat_map do |block|
          block_name = block["name"]
          next [] unless TEST_BLOCKS.include?(block_name)

          (block["jobs"] || []).map do |job|
            {
              id: job["jobid"],
              name: job["name"],
              block_name: block_name,
              result: block["result"]
            }
          end
        end
      end

      def fetch_log(job_id:)
        run_cmd("sem logs #{job_id}")
      end

      private

      def run_cmd(cmd)
        output = `#{cmd} 2>/dev/null`
        raise Error, "Command failed (exit #{$?.exitstatus}): #{cmd}" unless $?.success?
        output
      end

      def parse_workflow_line(line)
        parts = line.strip.split(/\s{2,}/)
        return nil if parts.length < 4

        {
          id: parts[0],
          pipeline_id: parts[1],
          branch: parts[3],
          created_at: parts[2]
        }
      end
    end

    Configuration.register_provider(:semaphore, Semaphore)
  end
end
