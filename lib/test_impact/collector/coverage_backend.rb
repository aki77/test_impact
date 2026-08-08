# frozen_string_literal: true

require "test_impact/collector/ddcov_backend"
require "test_impact/collector/null_backend"

module TestImpact
  module Collector
    module CoverageBackend
      UNAVAILABLE_MESSAGE = "test_impact: coverage backend unavailable, " \
                            "falling back to null backend (no coverage will be collected)"

      def self.build(config)
        return DdcovBackend.new(config) if DdcovBackend.available?(use_allocation_tracing: DdcovBackend.allocation_tracing?(config))

        if ENV["TEST_IMPACT_REQUIRE_COVERAGE"] == "1"
          raise CoverageUnavailableError, "coverage backend unavailable (TEST_IMPACT_REQUIRE_COVERAGE=1)"
        end

        $stderr.puts UNAVAILABLE_MESSAGE
        NullBackend.new
      end
    end
  end
end
