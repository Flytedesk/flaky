# frozen_string_literal: true

require "spec_helper"
require "flaky/log_parser"

RSpec.describe Flaky::LogParser do
  subject(:parser) { described_class.new }

  describe "#parse" do
    context "with a passing RSpec log" do
      let(:log) do
        <<~LOG
          Finished in 2 minutes 15.3 seconds (files took 6.14 seconds to load)
          275 examples, 0 failures

          Randomized with seed 63864
        LOG
      end

      it "extracts seed" do
        expect(parser.parse(log).seed).to eq(63864)
      end

      it "extracts example count" do
        expect(parser.parse(log).example_count).to eq(275)
      end

      it "extracts failure count" do
        expect(parser.parse(log).failure_count).to eq(0)
      end

      it "extracts duration" do
        expect(parser.parse(log).duration_seconds).to be_within(0.1).of(135.3)
      end

      it "returns no failures" do
        expect(parser.parse(log).failures).to be_empty
      end
    end

    context "with a failing RSpec log" do
      let(:log) do
        <<~LOG
          Finished in 4 minutes 27.4 seconds (files took 6.64 seconds to load)
          382 examples, 1 failure

          Failed examples:

          rspec ./packs/applications/admin/spec/system/inventory_ad_units_pages_spec.rb:528 # Inventory::AdUnit admin import ad unit calendar events makes file containing rejected records available for download

          Randomized with seed 6432
        LOG
      end

      it "extracts seed" do
        expect(parser.parse(log).seed).to eq(6432)
      end

      it "extracts example count" do
        expect(parser.parse(log).example_count).to eq(382)
      end

      it "extracts failure count" do
        expect(parser.parse(log).failure_count).to eq(1)
      end

      it "extracts the failure" do
        failures = parser.parse(log).failures
        expect(failures.length).to eq(1)
        expect(failures[0].spec_file).to eq("packs/applications/admin/spec/system/inventory_ad_units_pages_spec.rb")
        expect(failures[0].line_number).to eq(528)
        expect(failures[0].description).to include("rejected records available for download")
      end
    end

    context "with Semaphore line wrapping" do
      let(:log) do
        # Simulates ~80-char wrapping that splits filenames and words
        "Finished in 4 minutes 27.4 seconds (files took 6.64 seconds to load)\n" \
        "382 examples, 1 \n" \
        "failure\n" \
        "\n" \
        "Failed examples:\n" \
        "\n" \
        "rspec ./packs/applications/admin/spec/system/inventory_ad_un\n" \
        "its_pages_spec.rb:528 # Inventory::AdUnit admin import ad unit calendar events makes file c\n" \
        "ontaining rejected records available for download\n" \
        "\n" \
        "Randomized with seed 6432\n"
      end

      it "extracts failure count across wrapped lines" do
        expect(parser.parse(log).failure_count).to eq(1)
      end

      it "rejoins wrapped filenames" do
        failures = parser.parse(log).failures
        expect(failures.length).to eq(1)
        expect(failures[0].spec_file).to eq("packs/applications/admin/spec/system/inventory_ad_units_pages_spec.rb")
      end

      it "rejoins wrapped descriptions" do
        failures = parser.parse(log).failures
        expect(failures[0].description).to include("containing rejected records")
      end
    end

    context "with ANSI escape codes" do
      let(:log) do
        "\e[31m382 examples, 1 \n" \
        "failure\e[0m\n" \
        "\n" \
        "Failed examples:\n" \
        "\n" \
        "\e[31mrspec ./spec/foo_spec.rb:10\e[0m \e[36m# Foo does bar\e[0m\n" \
        "\n" \
        "Randomized with seed 999\n"
      end

      it "strips ANSI codes and parses correctly" do
        result = parser.parse(log)
        expect(result.failure_count).to eq(1)
        expect(result.seed).to eq(999)
        expect(result.failures.length).to eq(1)
        expect(result.failures[0].spec_file).to eq("spec/foo_spec.rb")
      end
    end

    context "with multiple failures" do
      let(:log) do
        <<~LOG
          Finished in 5 minutes 0 seconds (files took 3 seconds to load)
          500 examples, 3 failures

          Failed examples:

          rspec ./spec/a_spec.rb:10 # A does X
          rspec ./spec/b_spec.rb:20 # B does Y
          rspec ./spec/c_spec.rb:30 # C does Z

          Randomized with seed 11111
        LOG
      end

      it "extracts all failures" do
        failures = parser.parse(log).failures
        expect(failures.length).to eq(3)
        expect(failures.map(&:spec_file)).to eq(%w[spec/a_spec.rb spec/b_spec.rb spec/c_spec.rb])
        expect(failures.map(&:line_number)).to eq([10, 20, 30])
      end
    end

    context "with no RSpec output" do
      let(:log) { "some random build log with no test output" }

      it "returns nil/zero for all fields" do
        result = parser.parse(log)
        expect(result.seed).to be_nil
        expect(result.example_count).to be_nil
        expect(result.failure_count).to eq(0)
        expect(result.failures).to be_empty
      end
    end
  end
end
