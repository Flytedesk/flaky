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
  end
end
