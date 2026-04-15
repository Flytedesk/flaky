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
      def fetch_workflows(age: "24h")
        cutoff = Time.now - AgeParser.to_seconds(age)
        project_id = resolve_project_id
        branch = config.branch
        workflows = []

        page = 1
        loop do
          data = api_get("plumber-workflows", project_id: project_id, page: page)
          break if data.empty?

          data.each do |wf|
            created_at = Time.at(wf.dig("created_at", "seconds").to_i)
            next unless wf["branch_name"] == branch

            if created_at < cutoff
              return workflows # older than cutoff, done
            end

            workflows << {
              id: wf["wf_id"],
              pipeline_id: wf["initial_ppl_id"],
              branch: wf["branch_name"],
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
        query = params.map { |k, v| "#{k}=#{v}" }.join("&")
        url = "#{api_host}/api/v1alpha/#{path}"
        url += "?#{query}" unless query.empty?

        uri = URI(url)
        req = Net::HTTP::Get.new(uri)
        req["Authorization"] = "Token #{api_token}"

        response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true) do |http|
          http.request(req)
        end

        raise Error, "Semaphore API error (#{response.code}): #{response.body[0..200]}" unless response.is_a?(Net::HTTPSuccess)

        JSON.parse(response.body)
      rescue Net::OpenTimeout, Net::ReadTimeout => e
        raise Error, "Semaphore API timeout: #{e.message}"
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
