# Flaky

Track, rank, and reproduce flaky CI test failures in Rails projects.

Flaky fetches test results from your CI provider, stores failures in a local SQLite database, ranks tests by flakiness, and helps reproduce failures under simulated CI conditions.

## Installation

Add to your Gemfile:

```ruby
# From GitHub
gem 'flaky', github: 'Flytedesk/flaky', group: [:development, :test]

# Or from a local path during development
gem 'flaky', path: '../flaky', group: [:development, :test]
```

Then `bundle install`.

## Configuration

Create an initializer (e.g. `config/initializers/flaky.rb`):

```ruby
if defined?(Flaky)
  Flaky.configure do |c|
    c.provider = :semaphore        # or :github_actions
    c.project  = "my-project"      # CI project name
    c.branch   = "main"            # branch to track
  end
end
```

### Prerequisites by provider

**Semaphore**: Install and authenticate the [`sem` CLI](https://docs.semaphoreci.com/reference/sem-command-line-tool/).

**GitHub Actions**: Install and authenticate the [`gh` CLI](https://cli.github.com/).

## Rake Tasks

### `rake flaky:fetch[age]`

Fetch recent CI results and store failures in the local database.

```sh
rake flaky:fetch              # last 24 hours (default)
rake flaky:fetch[168h]        # last 7 days
rake flaky:fetch[2160h]       # last 90 days
```

For each workflow on the configured branch, fetches all test job logs, parses RSpec output for failures and random seeds, and inserts new records into `tmp/flaky.db`.

### `rake flaky:rank[since]`

Rank flaky tests by failure frequency and suggest the next one to investigate.

```sh
rake flaky:rank               # last 30 days (default)
rake flaky:rank[7]            # last 7 days
```

Output:

```
Flaky tests on main (last 30 days, 42 CI runs):

Fails  Location                                           Last Failure
------------------------------------------------------------------------------------------
5      ...spec/system/inventory_search_modal_spec.rb:83    2026-04-12 09:15:22

  > Next to investigate: packs/.../inventory_search_modal_spec.rb:83
    Inventory search modal filters by enrollment
    Seeds: 6432, 51203, 8891
```

### `rake flaky:history[spec_location]`

Show the full failure timeline for a specific test, including every seed and CI job it failed in.

```sh
rake flaky:history[inventory_search_modal_spec.rb:83]
rake flaky:history[inventory_search_modal_spec.rb]     # all failures in this file
```

### `rake flaky:stress[spec,iterations,seed,ci]`

Run a test repeatedly to reproduce a flaky failure or prove a fix is stable.

```sh
# 20 iterations with random seeds
rake flaky:stress[path/to/spec.rb:83]

# 50 iterations with a specific seed and CI simulation
rake flaky:stress[path/to/spec.rb:83,50,6432,true]
```

Arguments:
- `spec` (required) -- spec file path, optionally with line number
- `iterations` -- number of runs (default: 20)
- `seed` -- RSpec random seed; omit for random each run
- `ci` -- `true` to enable CI environment simulation (default: false)

Results are recorded to the database and shown in `rake flaky:report`.

### `rake flaky:report`

Summary dashboard showing overall flaky test health.

```sh
rake flaky:report
```

Output:

```
=== Flaky Test Report (main) ===

CI Runs tracked:     42
Failed runs:         8 (19.0%)
Total test failures: 14
Unique flaky specs:  6
Last fetch:          2026-04-14 20:39:57

7-day trend:         3 failures (prior 7 days: 5)
                     v Trending better

Top 5 flaky tests:
--------------------------------------------------------------------------------
  1. packs/.../inventory_search_modal_spec.rb:83 (5x)
     Inventory search modal filters by enrollment

Recent stress runs:
--------------------------------------------------------------------------------
  packs/.../inventory_search_modal_spec.rb:83 -- 18/20 passed (10.0% failure rate) [CI sim]
```

## CI Simulation

When `ci=true` is passed to `rake flaky:stress`, the gem simulates CI environment constraints:

1. **Rack middleware latency** -- adds 30ms delay per HTTP request (approximates the difference between a Mac and an f1-standard-2 CI machine). Configurable via `FLAKY_LATENCY_MS` env var.

2. **Reduced Puma threads** -- the host app should conditionally reduce Capybara's Puma threads when `FLAKY_CI_SIMULATE=1` is set:

```ruby
# spec/support/capybara_drivers.rb (or equivalent)
max_threads = ENV["FLAKY_CI_SIMULATE"] ? 2 : 8
Capybara.server = :puma, { Silent: true, Threads: "1:#{max_threads}" }
```

The middleware is auto-inserted by the Railtie in test environment when `FLAKY_CI_SIMULATE=1`.

## Database

Failures are stored in SQLite at `tmp/flaky.db` (auto-created on first use). The schema is managed internally and migrated automatically.

Tables:
- `ci_runs` -- one row per CI workflow on the tracked branch
- `job_results` -- one row per test job (unit tests, system tests, etc.)
- `test_failures` -- one row per individual test failure with spec file, line, description, and seed
- `stress_runs` -- one row per stress test session

The database is local and should be gitignored (typically already is via `tmp/`).

## Custom Providers

To add a CI provider, implement the three-method interface and register it:

```ruby
class Flaky::Providers::CircleCI < Flaky::Providers::Base
  def fetch_workflows(age: "24h")
    # Return [{ id:, pipeline_id:, branch:, created_at: }, ...]
  end

  def fetch_jobs(pipeline_id:)
    # Return [{ id:, name:, block_name:, result: }, ...]
  end

  def fetch_log(job_id:)
    # Return raw log string
  end
end

Flaky.register_provider(:circleci, Flaky::Providers::CircleCI)
```

The log parser is CI-agnostic -- it extracts failures, seeds, and counts from standard RSpec output. Your provider just needs to return the raw log text.

## Typical Workflow

```sh
# 1. Fetch recent CI data
rake flaky:fetch[168h]

# 2. See what's flaky
rake flaky:rank

# 3. Investigate the top offender
rake flaky:history[the_flaky_spec.rb:42]

# 4. Try to reproduce it locally with CI simulation
rake flaky:stress[the_flaky_spec.rb:42,30,6432,true]

# 5. Fix the test, then prove the fix holds
rake flaky:stress[the_flaky_spec.rb:42,50,,true]

# 6. Check overall health
rake flaky:report
```

## License

MIT
