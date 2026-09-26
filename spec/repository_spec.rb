# frozen_string_literal: true

require "spec_helper"
require "tmpdir"
require "flaky/repository"

RSpec.describe Flaky::Repository do
  subject(:repo) { described_class.new(File.join(Dir.mktmpdir, "flaky.db")) }

  after { repo.close }

  def record_failure(branch:, workflow_id:, spec_file: "spec/a_spec.rb", line_number: 1)
    now = Time.now.utc.strftime("%Y-%m-%d %H:%M:%S")
    unless repo.workflow_fetched?(workflow_id)
      repo.insert_ci_run(workflow_id: workflow_id, pipeline_id: "p-#{workflow_id}", branch: branch, result: "failed",
                         created_at: now)
    end
    job_id = "#{workflow_id}-#{spec_file}-#{line_number}"
    repo.insert_job_result(job_id: job_id, workflow_id: workflow_id, job_name: "Unit", block_name: "Unit Tests",
                           result: "failed", example_count: nil, failure_count: 1, seed: 1, duration_seconds: nil)
    repo.insert_test_failure(workflow_id: workflow_id, job_id: job_id, job_name: "Unit", spec_file: spec_file,
                             line_number: line_number, description: "d", seed: 1, branch: branch, failed_at: now)
  end

  describe "#rank_failures" do
    it "counts failures on every branch when asked for :all" do
      # given
      record_failure(branch: "main", workflow_id: "wf1")
      record_failure(branch: "feature-x", workflow_id: "wf2")

      # when
      rows = repo.rank_failures(branch: :all, since_days: 30)

      # then
      expect(rows.first["failure_count"]).to eq(2)
    end

    it "counts failures on the named branch only" do
      # given
      record_failure(branch: "main", workflow_id: "wf1")
      record_failure(branch: "feature-x", workflow_id: "wf2")

      # when
      rows = repo.rank_failures(branch: "main", since_days: 30)

      # then
      expect(rows.first["failure_count"]).to eq(1)
    end

    it "ranks a spec failing across branches above one failing repeatedly on a single branch" do
      # given
      3.times { |i| record_failure(branch: "broken-branch", workflow_id: "wf-b#{i}", spec_file: "spec/regression_spec.rb") }
      record_failure(branch: "main", workflow_id: "wf1", spec_file: "spec/flaky_spec.rb")
      record_failure(branch: "feature-x", workflow_id: "wf2", spec_file: "spec/flaky_spec.rb")

      # when
      rows = repo.rank_failures(branch: :all, since_days: 30)

      # then
      expect(rows.map { |r| [r["spec_file"], r["branch_count"]] })
        .to eq([["spec/flaky_spec.rb", 2], ["spec/regression_spec.rb", 1]])
    end
  end

  describe "#run_stats" do
    it "covers every branch when asked for :all" do
      # given
      record_failure(branch: "main", workflow_id: "wf1")
      record_failure(branch: "feature-x", workflow_id: "wf2")

      # when
      stats = repo.run_stats(branch: :all)

      # then
      expect(stats).to include(total_runs: 2, failed_runs: 2, total_failures: 2, unique_specs: 1)
    end
  end
end
