# frozen_string_literal: true

require "json"
require "net/http"
require "uri"
require "yaml"
require_relative "base"
require_relative "../age_parser"

module Flaky
  module Providers
    class Semaphore < Base
      MAX_ATTEMPTS = 3

      # Semaphore intermittently answers 500/504; worth another try.
      class TransientError < Error; end

      def fetch_workflows(age: "24h")
        cutoff = Time.now - AgeParser.to_seconds(age)
        project_id = resolve_project_id
        branch_filter = config.all_branches? ? {} : { branch_name: config.branch }
        workflows = []

        page = 1
        loop do
          data = api_get("plumber-workflows", project_id: project_id, **branch_filter, page: page)
          break if data.empty?

          data.each do |wf|
            created_at = Time.at(wf.dig("created_at", "seconds").to_i)
            if created_at < cutoff
              return workflows # older than cutoff, done
            end

            workflows << {
              id: wf["wf_id"],
              pipeline_id: wf["initial_ppl_id"],
              branch: wf["branch_name"],
              commit_sha: wf["commit_sha"],
              created_at: created_at.strftime("%Y-%m-%d %H:%M:%S")
            }
          end

          # If the oldest entry on this page is still within cutoff, keep paging
          oldest = Time.at(data.last.dig("created_at", "seconds").to_i)
          break if oldest < cutoff

          page += 1
        end

        workflows
      end

      def fetch_jobs(pipeline_id:)
        data = api_get("pipelines/#{pipeline_id}", detailed: true)
        blocks = data["blocks"] || []
        test_blocks = config.test_blocks

        blocks.flat_map do |block|
          block_name = block["name"]
          next [] unless test_blocks.include?(block_name)

          (block["jobs"] || []).map do |job|
            {
              id: job["job_id"],
              name: job["name"],
              block_name: block_name,
              result: job["result"]&.downcase == "passed" ? "passed" : "failed"
            }
          end
        end
      end

      def fetch_log(job_id:)
        data = api_get("logs/#{job_id}")
        events = data["events"] || []
        events
          .select { |e| e["event"] == "cmd_output" }
          .map { |e| e["output"] }
          .join
      end

      private

      def api_get(path, **params)
        query = URI.encode_www_form(params)
        url = "#{api_host}/api/v1alpha/#{path}"
        url += "?#{query}" unless query.empty?

        uri = URI(url)
        req = Net::HTTP::Get.new(uri)
        req["Authorization"] = "Token #{api_token}"

        attempt = 1
        begin
          response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
            http.request(req)
          end

          message = "Semaphore API error (#{response.code}): #{response.body[0..200]}"
          raise TransientError, message if response.is_a?(Net::HTTPServerError)
          raise Error, message unless response.is_a?(Net::HTTPSuccess)

          JSON.parse(response.body)
        rescue TransientError, Net::OpenTimeout, Net::ReadTimeout => e
          raise Error, "#{e.message} (gave up after #{attempt} attempts)" if attempt >= MAX_ATTEMPTS

          sleep(2**attempt)
          attempt += 1
          retry
        end
      rescue SocketError => e
        raise Error, "Cannot reach Semaphore API: #{e.message}"
      rescue Errno::ECONNREFUSED => e
        raise Error, "Connection refused to Semaphore API: #{e.message}"
      rescue JSON::ParserError => e
        raise Error, "Invalid JSON from Semaphore API: #{e.message}"
      end

      def sem_config
        @sem_config ||= begin
          path = File.expand_path("~/.sem.yaml")
          unless File.exist?(path)
            raise Error, "Semaphore config not found at #{path}. Run `sem connect` to authenticate."
          end
          YAML.safe_load_file(path)
        end
      end

      def api_host
        @api_host ||= begin
          context_name = sem_config["active-context"]
          host = sem_config.dig("contexts", context_name, "host")
          raise Error, "No host found in ~/.sem.yaml for context '#{context_name}'" unless host
          "https://#{host}"
        end
      end

      def api_token
        @api_token ||= begin
          context_name = sem_config["active-context"]
          token = sem_config.dig("contexts", context_name, "auth", "token")
          raise Error, "No auth token found in ~/.sem.yaml for context '#{context_name}'" unless token
          token
        end
      end

      def resolve_project_id
        @project_id ||= begin
          projects = api_get("projects")
          project = projects.find { |p| p.dig("metadata", "name") == config.project }
          raise Error, "Project '#{config.project}' not found in Semaphore" unless project
          project.dig("metadata", "id")
        end
      end
    end

    Configuration.register_provider(:semaphore, Semaphore)
  end
end
