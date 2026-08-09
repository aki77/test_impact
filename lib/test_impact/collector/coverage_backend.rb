# frozen_string_literal: true

require 'test_impact/collector/ddcov_backend'
require 'test_impact/collector/null_backend'

module TestImpact
  module Collector
    # Chooses the coverage backend for this process: the native ddcov backend
    # when it loads, otherwise a hard failure unless the caller opted out.
    module CoverageBackend
      UNAVAILABLE_MESSAGE = 'test_impact: coverage backend unavailable, ' \
                            'falling back to null backend because TEST_IMPACT_REQUIRE_COVERAGE ' \
                            'opts out (no coverage will be collected)'

      # Spelled generously on purpose: unlike an opt-in flag, a misspelled
      # opt-out fails the collection job, and the typo only surfaces on the
      # day the backend actually breaks.
      OPT_OUT_VALUES = %w[0 false no off].freeze

      def self.build(config)
        # Bind once: both lookups memoize per parameter, so they must be
        # asked about the very same one.
        allocation_tracing = DdcovBackend.allocation_tracing?(config)
        reason = DdcovBackend.unavailable_reason(use_allocation_tracing: allocation_tracing)
        return DdcovBackend.new(config) if reason.nil?

        # Collecting coverage is the only reason this process runs, so an
        # unusable backend is a hard failure unless explicitly opted out of.
        raise CoverageUnavailableError, unavailable_error_message(reason) unless opted_out?

        warn UNAVAILABLE_MESSAGE
        NullBackend.new
      end

      def self.opted_out?
        OPT_OUT_VALUES.include?(ENV['TEST_IMPACT_REQUIRE_COVERAGE'].to_s.strip.downcase)
      end

      # Spelled out for operators who only ever see the CI log.
      def self.unavailable_error_message(reason)
        "test_impact: coverage backend unavailable (#{reason.class}: #{reason.message}). " \
          'Set TEST_IMPACT_REQUIRE_COVERAGE=0 to fall back to the null backend instead ' \
          '(the map is then tagged as invalid and every spec runs).'
      end
    end
  end
end
