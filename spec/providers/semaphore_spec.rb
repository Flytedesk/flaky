# frozen_string_literal: true

require "spec_helper"

RSpec.describe Flaky::Providers::Semaphore do
  subject(:provider) { described_class.new(config) }

  let(:config) do
    Flaky::Configuration.new.tap do |c|
      c.provider = :semaphore
      c.project = "my-project"
      c.branch = "main"
    end
  end
  let(:requested_paths) { [] }
  let(:responses) do
    {
      "projects" => [ok([{ "metadata" => { "name" => "my-project", "id" => "p1" } }])],
      "plumber-workflows" => [ok([])]
    }
  end

  before do
    allow(provider).to receive(:sem_config).and_return(
      "active-context" => "ctx",
      "contexts" => { "ctx" => { "host" => "example.semaphoreci.com", "auth" => { "token" => "t" } } }
    )
    http = instance_double(Net::HTTP)
    allow(http).to receive(:request) do |req|
      requested_paths << req.path
      endpoint = req.path.delete_prefix("/api/v1alpha/").split("?").first
      queue = responses.fetch(endpoint)
      queue.length > 1 ? queue.shift : queue.first
    end
    allow(Net::HTTP).to receive(:start).and_yield(http)
  end

  def ok(body)
    response("200", body)
  end

  def response(code, body)
    Net::HTTPResponse::CODE_TO_OBJ.fetch(code).new("1.1", code, "").tap do |r|
      allow(r).to receive(:body).and_return(body.is_a?(String) ? body : JSON.generate(body))
    end
  end

  describe "#fetch_workflows" do
    it "asks Semaphore for the configured branch only" do
      # when
      provider.fetch_workflows(age: "24h")

      # then
      expect(requested_paths).to include(a_string_matching(/plumber-workflows\?.*branch_name=main/))
    end

    it "asks Semaphore for every branch when configured with :all" do
      # given
      config.branch = :all

      # when
      provider.fetch_workflows(age: "24h")

      # then
      expect(requested_paths.grep(/plumber-workflows/)).to all(satisfy { |path| !path.include?("branch_name") })
    end
  end

  describe "#fetch_jobs" do
    it "reports a job Semaphore stopped as stopped, not failed" do
      # given
      responses["pipelines/ppl1"] = [ok("blocks" => [
        { "name" => "Unit Tests", "jobs" => [{ "job_id" => "j1", "name" => "Unit 1/2", "result" => "STOPPED" }] }
      ])]

      # when
      jobs = provider.fetch_jobs(pipeline_id: "ppl1")

      # then
      expect(jobs.map { |j| j[:result] }).to eq(["stopped"])
    end
  end

  describe "transient API errors" do
    before { allow(provider).to receive(:sleep) }

    it "retries a request that returned a server error" do
      # given
      responses["plumber-workflows"] = [response("500", '"Internal error"'), ok([])]

      # when
      workflows = provider.fetch_workflows(age: "24h")

      # then
      expect(workflows).to eq([])
    end

    it "retries a request that timed out" do
      # given
      calls = 0
      allow(Net::HTTP).to receive(:start) do |&block|
        calls += 1
        raise Net::ReadTimeout if calls == 1

        block.call(instance_double(Net::HTTP, request: ok([])))
      end

      # when
      provider.send(:api_get, "plumber-workflows")

      # then
      expect(calls).to eq(2)
    end

    it "gives up after 3 attempts" do
      # given
      responses["plumber-workflows"] = [response("500", '"Internal error"')]

      # when / then
      expect { provider.fetch_workflows(age: "24h") }
        .to raise_error(Flaky::Error, /\(500\).*gave up after 3 attempts/)
    end
  end
end
