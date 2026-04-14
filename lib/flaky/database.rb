# frozen_string_literal: true

require "sqlite3"

module Flaky
  class Database
    SCHEMA_VERSION = 1

    def initialize(path = nil)
      @path = path || Flaky.configuration.resolved_db_path
    end

    def connection
      @connection ||= begin
        dir = File.dirname(@path)
        FileUtils.mkdir_p(dir) unless File.directory?(dir)
        db = SQLite3::Database.new(@path)
        db.results_as_hash = true
        db.execute("PRAGMA journal_mode=WAL")
        db.execute("PRAGMA foreign_keys=ON")
        migrate!(db)
        db
      end
    end

    def close
      @connection&.close
      @connection = nil
    end

    private

    def migrate!(db)
      version = db.get_first_value("PRAGMA user_version").to_i

      if version < 1
        db.execute_batch(<<~SQL)
          CREATE TABLE IF NOT EXISTS ci_runs (
            workflow_id TEXT PRIMARY KEY,
            pipeline_id TEXT NOT NULL,
            branch TEXT NOT NULL,
            result TEXT NOT NULL,
            created_at TEXT NOT NULL,
            fetched_at TEXT NOT NULL DEFAULT (datetime('now'))
          );

          CREATE TABLE IF NOT EXISTS job_results (
            job_id TEXT PRIMARY KEY,
            workflow_id TEXT NOT NULL REFERENCES ci_runs(workflow_id),
            job_name TEXT NOT NULL,
            block_name TEXT NOT NULL,
            result TEXT NOT NULL,
            example_count INTEGER,
            failure_count INTEGER,
            seed INTEGER,
            duration_seconds REAL,
            fetched_at TEXT NOT NULL DEFAULT (datetime('now'))
          );

          CREATE TABLE IF NOT EXISTS test_failures (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            workflow_id TEXT NOT NULL REFERENCES ci_runs(workflow_id),
            job_id TEXT NOT NULL REFERENCES job_results(job_id),
            job_name TEXT NOT NULL,
            spec_file TEXT NOT NULL,
            line_number INTEGER NOT NULL,
            description TEXT NOT NULL,
            seed INTEGER NOT NULL,
            branch TEXT NOT NULL,
            failed_at TEXT NOT NULL,
            UNIQUE(workflow_id, spec_file, line_number)
          );

          CREATE TABLE IF NOT EXISTS stress_runs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            spec_location TEXT NOT NULL,
            seed INTEGER,
            iterations INTEGER NOT NULL,
            passes INTEGER NOT NULL DEFAULT 0,
            failures INTEGER NOT NULL DEFAULT 0,
            ci_simulation INTEGER NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL DEFAULT (datetime('now'))
          );

          CREATE INDEX IF NOT EXISTS idx_test_failures_spec ON test_failures(spec_file, line_number);
          CREATE INDEX IF NOT EXISTS idx_test_failures_branch ON test_failures(branch);
          CREATE INDEX IF NOT EXISTS idx_ci_runs_branch ON ci_runs(branch);
          CREATE INDEX IF NOT EXISTS idx_job_results_workflow ON job_results(workflow_id);

          PRAGMA user_version = 1;
        SQL
      end
    end
  end
end
