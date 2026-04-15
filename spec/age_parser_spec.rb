# frozen_string_literal: true

require "spec_helper"
require "flaky/age_parser"

RSpec.describe Flaky::AgeParser do
  describe ".to_seconds" do
    it "parses hours" do
      expect(described_class.to_seconds("24h")).to eq(86400)
      expect(described_class.to_seconds("1h")).to eq(3600)
    end

    it "parses days" do
      expect(described_class.to_seconds("7d")).to eq(604800)
      expect(described_class.to_seconds("1d")).to eq(86400)
    end

    it "parses minutes" do
      expect(described_class.to_seconds("30m")).to eq(1800)
      expect(described_class.to_seconds("5m")).to eq(300)
    end

    it "defaults to 24h for unrecognized formats" do
      expect(described_class.to_seconds("garbage")).to eq(86400)
      expect(described_class.to_seconds("")).to eq(86400)
      expect(described_class.to_seconds(nil)).to eq(86400)
    end
  end
end
