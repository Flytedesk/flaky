# frozen_string_literal: true

require_relative "database"

module Flaky
  class Repository
    def initialize(path = nil)
      @db = Database.new(path)
    end

    def close
      @db.close
    end

    # --- CI Runs ---

    def workflow_fetched?(workflow_id)
      !!connection.get_first_value("SELECT 1 FROM ci_runs WHERE workflow_id = ?", workflow_id)
    end

    def insert_ci_run(workflow_id:, pipeline_id:, branch:, result:, created_at:, commit_sha: nil)
      connection.execute(
        "INSERT INTO ci_runs (workflow_id, pipeline_id, branch, result, created_at, commit_sha) VALUES (?, ?, ?, ?, ?, ?)",
        [workflow_id, pipeline_id, branch, result, created_at, commit_sha]
      )
    end

    # --- Job Results ---

    def insert_job_result(job_id:, workflow_id:, job_name:, block_name:, result:, example_count:, failure_count:, seed:, duration_seconds:)
      connection.execute(
        "INSERT OR IGNORE INTO job_results (job_id, workflow_id, job_name, block_name, result, example_count, failure_count, seed, duration_seconds) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [job_id, workflow_id, job_name, block_name, result, example_count, failure_count, seed, duration_seconds]
      )
    end

    # --- Test Failures ---

    def insert_test_failure(workflow_id:, job_id:, job_name:, spec_file:, line_number:, description:, seed:, branch:, failed_at:)
      connection.execute(
        "INSERT OR IGNORE INTO test_failures (workflow_id, job_id, job_name, spec_file, line_number, description, seed, branch, failed_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)",
        [workflow_id, job_id, job_name, spec_file, line_number, description, seed, branch, failed_at]
      )
    end

    # --- Ranking ---

    def rank_failures(branch:, since_days:, min_failures: 1)
      connection.execute(<<~SQL, [branch, "-#{since_days} days", min_failures])
        SELECT
          tf.spec_file,
          tf.line_number,
          tf.description,
          COUNT(*) as failure_count,
          MAX(tf.failed_at) as last_failure,
          GROUP_CONCAT(DISTINCT tf.seed) as seeds,
          GROUP_CONCAT(DISTINCT cr.commit_sha) as commit_shas
        FROM test_failures tf
        JOIN ci_runs cr ON cr.workflow_id = tf.workflow_id
        WHERE cr.branch = ?
          AND cr.created_at >= datetime('now', ?)
        GROUP BY tf.spec_file, tf.line_number
        HAVING COUNT(*) >= ?
        ORDER BY failure_count DESC, last_failure DESC
      SQL
    end

    def total_runs_count(branch:, since_days:)
      connection.get_first_value(
        "SELECT COUNT(DISTINCT workflow_id) FROM ci_runs WHERE branch = ? AND created_at >= datetime('now', ?)",
        [branch, "-#{since_days} days"]
      ).to_i
    end

    # --- History ---

    def failure_history(file:, line: nil)
      conditions = ["tf.spec_file LIKE ?"]
      params = ["%#{file}%"]

      if line
        conditions << "tf.line_number = ?"
        params << line
      end

      connection.execute(<<~SQL, params)
        SELECT
          tf.spec_file,
          tf.line_number,
          tf.description,
          tf.seed,
          tf.job_name,
          tf.branch,
          tf.failed_at,
          cr.workflow_id,
          cr.commit_sha
        FROM test_failures tf
        JOIN ci_runs cr ON cr.workflow_id = tf.workflow_id
        WHERE #{conditions.join(" AND ")}
        ORDER BY tf.failed_at DESC
      SQL
    end

    # --- Report ---

    def run_stats(branch:)
      {
        total_runs: connection.get_first_value("SELECT COUNT(*) FROM ci_runs WHERE branch = ?", branch).to_i,
        failed_runs: connection.get_first_value("SELECT COUNT(*) FROM ci_runs WHERE branch = ? AND result = 'failed'", branch).to_i,
        total_failures: connection.get_first_value("SELECT COUNT(*) FROM test_failures WHERE branch = ?", branch).to_i,
        unique_specs: connection.get_first_value("SELECT COUNT(DISTINCT spec_file || ':' || line_number) FROM test_failures WHERE branch = ?", branch).to_i,
        last_fetch: connection.get_first_value("SELECT MAX(fetched_at) FROM ci_runs")
      }
    end

    def failure_trend(branch:, period_days: 7)
      recent = connection.get_first_value(
        "SELECT COUNT(*) FROM test_failures WHERE branch = ? AND failed_at >= datetime('now', ?)",
        [branch, "-#{period_days} days"]
      ).to_i

      prior = connection.get_first_value(
        "SELECT COUNT(*) FROM test_failures WHERE branch = ? AND failed_at >= datetime('now', ?) AND failed_at < datetime('now', ?)",
        [branch, "-#{period_days * 2} days", "-#{period_days} days"]
      ).to_i

      { recent: recent, prior: prior }
    end

    def top_flaky(branch:, limit: 5)
      connection.execute(<<~SQL, [branch, limit])
        SELECT
          spec_file,
          line_number,
          description,
          COUNT(*) as failure_count,
          MAX(failed_at) as last_failure
        FROM test_failures
        WHERE branch = ?
        GROUP BY spec_file, line_number
        ORDER BY failure_count DESC
        LIMIT ?
      SQL
    end

    def recent_stress_runs(limit: 3)
      connection.execute("SELECT * FROM stress_runs ORDER BY created_at DESC LIMIT ?", limit)
    end

    # --- Seeds ---

    def failing_seeds(file:, line: nil)
      conditions = ["spec_file LIKE ?"]
      params = ["%#{file}%"]

      if line
        conditions << "line_number = ?"
        params << line
      end

      connection.execute(
        "SELECT DISTINCT seed FROM test_failures WHERE #{conditions.join(' AND ')} ORDER BY failed_at DESC",
        params
      ).map { |row| row["seed"] }
    end

    # --- Stress ---

    def insert_stress_run(spec_location:, seed:, iterations:, passes:, failures:, ci_simulation:)
      connection.execute(
        "INSERT INTO stress_runs (spec_location, seed, iterations, passes, failures, ci_simulation) VALUES (?, ?, ?, ?, ?, ?)",
        [spec_location, seed, iterations, passes, failures, ci_simulation]
      )
    end

    private

    def connection
      @db.connection
    end
  end
end
