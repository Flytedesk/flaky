# frozen_string_literal: true

module Flaky
  module AgeParser
    # Parses a human-friendly age string ("24h", "7d", "30m") into seconds.
    # Returns 86400 (24h) for unrecognized formats.
    def self.to_seconds(age)
      case age.to_s
      when /\A(\d+)h\z/ then $1.to_i * 3600
      when /\A(\d+)d\z/ then $1.to_i * 86400
      when /\A(\d+)m\z/ then $1.to_i * 60
      else 86400
      end
    end
  end
end
