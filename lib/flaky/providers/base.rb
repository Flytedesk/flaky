# frozen_string_literal: true

module Flaky
  module Providers
    class Base
      attr_reader :config

      def initialize(config)
        @config = config
      end

      # Returns Array of Hashes:
      #   { id:, pipeline_id:, branch:, result:, created_at: }
      def fetch_workflows(age: "24h")
        raise NotImplementedError
      end

      # Returns Array of Hashes:
      #   { id:, name:, block_name:, result: }
      def fetch_jobs(pipeline_id:)
        raise NotImplementedError
      end

      # Returns raw log String for a job
      def fetch_log(job_id:)
        raise NotImplementedError
      end
    end
  end
end
