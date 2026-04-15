# frozen_string_literal: true

require_relative "../repository"

module Flaky
  module Commands
    class Stress
      def initialize(spec_location:, iterations: 20, seed: nil, ci_simulate: false, timeout: 600)
        @spec_location = spec_location
        @iterations = iterations
        @seed = seed
        @ci_simulate = ci_simulate
        @timeout = timeout
        @repo = Repository.new
      end

      def execute
        env = {}
        env["FLAKY_CI_SIMULATE"] = "1" if @ci_simulate

        seeds = resolve_seeds
        passes = 0
        failures = 0
        failed_seeds = []
        start_time = Time.now

        puts "Stress testing: #{@spec_location}"
        puts "  Iterations: #{@iterations}, Seeds: #{seed_description(seeds)}, CI simulation: #{@ci_simulate}"
        puts ""

        @iterations.times do |i|
          elapsed = Time.now - start_time
          if elapsed > @timeout
            puts "\n\nTimeout reached (#{@timeout}s) after #{i} iterations."
            break
          end

          run_seed = seeds ? seeds[i % seeds.length] : rand(100_000)
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

        @repo.insert_stress_run(
          spec_location: @spec_location, seed: @seed.is_a?(Integer) ? @seed : nil,
          iterations: @iterations, passes: passes, failures: failures,
          ci_simulation: @ci_simulate ? 1 : 0
        )

        exit(failures > 0 ? 1 : 0)
      ensure
        @repo.close
      end

      private

      def resolve_seeds
        case @seed
        when :random
          nil
        when Integer
          [@seed]
        when nil
          file, line = parse_location(@spec_location)
          db_seeds = @repo.failing_seeds(file: file, line: line)
          if db_seeds.any?
            puts "Found #{db_seeds.length} known failing seed(s): #{db_seeds.join(', ')}"
            db_seeds
          else
            puts "No known failing seeds — using random."
            nil
          end
        end
      end

      def seed_description(seeds)
        case @seed
        when :random then "random"
        when Integer then @seed.to_s
        else seeds ? "#{seeds.length} from database" : "random"
        end
      end

      def parse_location(loc)
        if loc.include?(":")
          parts = loc.rpartition(":")
          [parts[0], parts[2].to_i]
        else
          [loc, nil]
        end
      end
    end
  end
end
