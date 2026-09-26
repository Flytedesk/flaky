# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "stringio"
require "flaky/commands/fetch"

RSpec.describe Flaky::Commands::Fetch do
  let(:db_path) { File.join(Dir.mktmpdir, "flaky.db") }
  let(:provider) { instance_double(Flaky::Providers::Base) }
  let(:workflow) do
    { id: "wf1", pipeline_id: "ppl1", branch: "main", commit_sha: "abc", created_at: "2026-09-25 14:40:18" }
  end
  let(:jobs) do
    [
      { id: "job1", name: "Unit 1/2", block_name: "Unit Tests", result: "passed" },
      { id: "job2", name: "Unit 2/2", block_name: "Unit Tests", result: "passed" }
    ]
  end

  before do
    config = Flaky::Configuration.new.tap { |c| c.db_path = db_path }
    allow(Flaky).to receive_messages(configuration: config, provider: provider)
    allow(provider).to receive_messages(fetch_workflows: [workflow], fetch_jobs: jobs)
  end

  around do |example|
    original = $stdout
    $stdout = StringIO.new
    example.run
  ensure
    $stdout = original
  end

  def repository
    Flaky::Repository.new(db_path)
  end

  it "leaves no trace of a workflow whose jobs could not all be fetched" do
    # given
    allow(provider).to receive(:fetch_log).with(job_id: "job1").and_return("10 examples, 0 failures")
    allow(provider).to receive(:fetch_log).with(job_id: "job2").and_raise(Flaky::Error, "Semaphore API error (504)")

    # when
    expect { described_class.new.execute }.to raise_error(Flaky::Error)

    # then
    expect(repository.workflow_fetched?("wf1")).to be(false)
  end
end
