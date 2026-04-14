# frozen_string_literal: true

require_relative "../database"

module Flaky
  module Commands
    class Stress
      def initialize(spec_location:, iterations: 20, seed: nil, ci_simulate: false, timeout: 600)
        @spec_location = spec_location
        @iterations = iterations
        @seed = seed
        @ci_simulate = ci_simulate
        @timeout = timeout
        @db = Database.new
      end

      def execute
        env = {}
        env["FLAKY_CI_SIMULATE"] = "1" if @ci_simulate

        passes = 0
        failures = 0
        failed_seeds = []
        start_time = Time.now

        puts "Stress testing: #{@spec_location}"
        puts "  Iterations: #{@iterations}, Seed: #{@seed || 'random'}, CI simulation: #{@ci_simulate}"
        puts ""

        @iterations.times do |i|
          elapsed = Time.now - start_time
          if elapsed > @timeout
            puts "\n\nTimeout reached (#{@timeout}s) after #{i} iterations."
            break
          end

          run_seed = @seed || rand(100_000)
          cmd = "bundle exec rspec #{@spec_location} --seed #{run_seed} --format progress 2>&1"

          output = nil
          success = nil
          IO.popen(env, cmd) do |io|
            output = io.read
            io.close
            success = $?.success?
          end

          if success
            passes += 1
            print "\e[32m.\e[0m"
          else
            failures += 1
            failed_seeds << run_seed
            print "\e[31mF\e[0m"
          end
        end

        total = passes + failures
        rate = total > 0 ? (failures.to_f / total * 100).round(1) : 0

        puts "\n\n#{total} runs: #{passes} passed, #{failures} failed"
        puts "Failure rate: #{rate}%"

        if failed_seeds.any?
          puts "Failed seeds: #{failed_seeds.join(', ')}"
          puts "\nTo reproduce a specific failure:"
          puts "  FLAKY_CI_SIMULATE=#{@ci_simulate ? '1' : '0'} bundle exec rspec #{@spec_location} --seed #{failed_seeds.first}"
        end

        # Record to database
        conn = @db.connection
        conn.execute(
          "INSERT INTO stress_runs (spec_location, seed, iterations, passes, failures, ci_simulation) VALUES (?, ?, ?, ?, ?, ?)",
          [@spec_location, @seed, @iterations, passes, failures, @ci_simulate ? 1 : 0]
        )

        exit(failures > 0 ? 1 : 0)
      ensure
        @db.close
      end
    end
  end
end
