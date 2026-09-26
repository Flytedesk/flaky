# Flaky

A Ruby gem for tracking and reproducing flaky CI test failures in Rails projects.

## Architecture

```
lib/flaky/
  configuration.rb          # Config DSL + provider registry
  railtie.rb                # Rails integration (rake tasks + middleware)
  database.rb               # SQLite schema + connection (auto-migrating)
  log_parser.rb             # RSpec output parser (CI-agnostic)
  providers/
    base.rb                 # Abstract provider interface (3 methods)
    semaphore.rb            # Semaphore CI via its REST API (token from ~/.sem.yaml)
    github_actions.rb       # GitHub Actions via `gh` CLI
  commands/
    fetch.rb                # Provider -> Parser -> DB pipeline
    rank.rb                 # Failure frequency ranking
    history.rb              # Per-test failure timeline
    stress.rb               # Repeated test runner with CI simulation
    report.rb               # Summary dashboard
  middleware/
    simulate_ci_latency.rb  # Rack middleware adding per-request delay
  tasks/
    flaky.rake              # Rake task definitions (thin wrappers around commands)
```

## Key Design Decisions

- **Pluggable providers**: CI-specific code is isolated in `providers/`. The `Base` class defines the contract: `fetch_workflows`, `fetch_jobs`, `fetch_log`. Commands and the log parser never touch CI-specific code. A job's `result` comes from the provider, not the log, so jobs that die before RSpec runs are still recorded as failed.

- **Semaphore API quirks**: `plumber-workflows` pages 30 at a time across all branches unless given `branch_name`, and intermittently answers 500; `/logs/{job}` 504s on large logs. `api_get` retries server errors and timeouts (`MAX_ATTEMPTS`).

- **Atomic fetch**: `Fetch` stores a workflow and all its job results in one transaction. A row in `ci_runs` means "done" and is never revisited, so it must not exist without its jobs.

- **CI-agnostic log parser**: `LogParser` operates on raw RSpec output from any provider. It handles Semaphore's ~80-char line wrapping by stripping newlines from the "Failed examples:" section before regex extraction.

- **SQLite storage**: `tmp/flaky.db`, auto-created and auto-migrated on first access. Schema version tracked via `PRAGMA user_version`. No external migration tooling needed.

- **Railtie integration**: Rake tasks are loaded automatically. The `SimulateCiLatency` middleware is inserted only when `FLAKY_CI_SIMULATE=1` and `RAILS_ENV=test`.

- **Provider registration**: Providers self-register at require time via `Configuration.register_provider`. Both built-in providers are required in `lib/flaky.rb`.

## Working with the Code

### Running from a host Rails app

The gem is added to a host app's Gemfile. Rake tasks become available automatically via the Railtie. Configuration lives in the host app's initializer.

### Log parsing gotchas

Semaphore wraps log output at ~80 characters, splitting tokens mid-word. The parser handles this by:
1. Stripping ANSI escape codes
2. Using `scan` with `.last` for summary fields (seed, example count, failure count) to skip early matches from RSpec config output
3. Removing newlines entirely (not replacing with space) in the "Failed examples:" section to rejoin split filenames

### Database schema changes

Bump `SCHEMA_VERSION` in `database.rb` and add a new migration block in `migrate!`. The version check uses `PRAGMA user_version`.

### Adding a new command

1. Create `lib/flaky/commands/my_command.rb` implementing `#execute`
2. Add a rake task in `lib/flaky/tasks/flaky.rake` that requires and invokes it

### Adding a new provider

1. Create `lib/flaky/providers/my_provider.rb` extending `Flaky::Providers::Base`
2. Implement `fetch_workflows(age:)`, `fetch_jobs(pipeline_id:)`, `fetch_log(job_id:)`
3. Call `Configuration.register_provider(:my_provider, MyProvider)` at the bottom of the file
4. Add `require_relative "flaky/providers/my_provider"` in `lib/flaky.rb`

## Dependencies

- `sqlite3` (~> 2.0) -- database
- `railties` (>= 7.0) -- Railtie integration
- Ruby >= 3.1

External CLI tools (not gem dependencies):
- `sem` -- only to create `~/.sem.yaml` (`sem connect`) for the Semaphore provider
- `gh` -- for the GitHub Actions provider

## Testing

```sh
bundle exec rspec
```

Specs cover the log parser, age parser, Semaphore provider (`Net::HTTP` stubbed), and fetch command (temp SQLite db). CI runs them on Ruby 3.4 and 4.0.

Smoke-test against real CI from the host Rails app:

```sh
bin/rails flaky:fetch DURATION=24h
bin/rails flaky:rank
bin/rails flaky:report
```
