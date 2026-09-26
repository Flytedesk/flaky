# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "flaky/commands/rank"

RSpec.describe Flaky::Commands::Rank do
  let(:db_path) { File.join(Dir.mktmpdir, "flaky.db") }

  before do
    config = Flaky::Configuration.new.tap do |c|
      c.db_path = db_path
      c.branch = :all
    end
    allow(Flaky).to receive(:configuration).and_return(config)

    repo = Flaky::Repository.new(db_path)
    now = Time.now.utc.strftime("%Y-%m-%d %H:%M:%S")
    %w[main feature-x].each do |branch|
      repo.insert_ci_run(workflow_id: branch, pipeline_id: branch, branch: branch, result: "failed", created_at: now)
      repo.insert_job_result(job_id: branch, workflow_id: branch, job_name: "Unit", block_name: "Unit Tests",
                             result: "failed", example_count: nil, failure_count: 1, seed: 1, duration_seconds: nil)
      repo.insert_test_failure(workflow_id: branch, job_id: branch, job_name: "Unit", spec_file: "spec/a_spec.rb",
                               line_number: 7, description: "d", seed: 1, branch: branch, failed_at: now)
    end
    repo.close
  end

  it "shows how many branches each spec failed on" do
    # when / then
    expect { described_class.new.execute }
      .to output(%r{^2\s+2\s+spec/a_spec\.rb:7}).to_stdout
  end
end
