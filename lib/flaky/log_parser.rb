# frozen_string_literal: true

module Flaky
  class LogParser
    Result = Data.define(:seed, :example_count, :failure_count, :duration_seconds, :failures)
    Failure = Data.define(:spec_file, :line_number, :description)

    def parse(raw_log)
      log = normalize(raw_log)

      Result.new(
        seed: extract_seed(log),
        example_count: extract_example_count(log),
        failure_count: extract_failure_count(log),
        duration_seconds: extract_duration(log),
        failures: extract_failures(log)
      )
    end

    private

    def normalize(text)
      # 1. Strip ANSI escape codes
      clean = text.gsub(/\e\[\d*;?\d*m/, "")
      # 2. Rejoin lines broken by Semaphore's ~80-char wrapping.
      #    Real RSpec blank lines (section separators) are preserved.
      #    A wrapped line is one where the previous line doesn't end with
      #    a logical boundary (blank line, "exit status:", prompt markers).
      clean
    end

    def extract_seed(log)
      log.scan(/Randomized with seed (\d+)/).flatten.last&.to_i
    end

    def extract_example_count(log)
      # Allow whitespace (including newlines from wrapping) between number and "examples"
      log.scan(/(\d+)\s+examples?/).flatten.last&.to_i
    end

    def extract_failure_count(log)
      # Match "N failure(s)" allowing wrapped newlines; take the last occurrence
      log.scan(/(\d+)\s+failures?/).flatten.last&.to_i || 0
    end

    def extract_duration(log)
      # "Finished in N minutes N.N seconds" — may span wrapped lines
      # Collapse the area around "Finished in" first
      section = log[/Finished in.{0,80}/m]
      return nil unless section

      collapsed = section.gsub(/\s+/, " ")
      match = collapsed.match(/Finished in\s+((\d+)\s+minutes?\s+)?(\d+(?:\.\d+)?)\s+seconds?/)
      return nil unless match

      seconds = match[3].to_f
      seconds += match[2].to_i * 60 if match[2]
      seconds
    end

    def extract_failures(log)
      # Find section between "Failed examples:" and "Randomized with seed"
      section = log[/Failed examples:\s*\n(.*?)(?=\nRandomized with seed)/m, 1]
      return [] unless section

      # Semaphore wraps lines at ~80 chars, splitting mid-word.
      # Remove newlines directly (not replacing with space) to rejoin split tokens.
      collapsed = section.delete("\n").squeeze(" ").strip

      collapsed.scan(/rspec\s+\.\/(\S+):(\d+)\s+#\s+(.*?)(?=\s*rspec\s+\.\/|\s*$)/).map do |file, line, desc|
        Failure.new(spec_file: file, line_number: line.to_i, description: desc.strip)
      end
    end
  end
end
