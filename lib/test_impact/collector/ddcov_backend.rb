# frozen_string_literal: true

require "test_impact/paths"

module TestImpact
  module Collector
    class DdcovBackend
      NATIVE_REQUIRE_PATH = "datadog_ci_native.#{RUBY_VERSION}_#{RUBY_PLATFORM}"
      DDCOV_CONST = "Datadog::CI::TestImpactAnalysis::Coverage::DDCov"

      class << self
        # Probes with the same parameters the real instance will use
        # (ignored_path and allocation tracing included), so a code path that
        # only breaks under the real configuration still fails safe here.
        def available?(use_allocation_tracing: true)
          probe(use_allocation_tracing).nil?
        end

        # The exception that made the probe fail, or nil when the backend is
        # available. Callers that turn unavailability into a hard failure need
        # it to tell the user *why* ddcov could not load.
        def unavailable_reason(use_allocation_tracing: true)
          probe(use_allocation_tracing)
        end

        def allocation_tracing?(config)
          config.collector["allocation_tracing"] ? true : false
        end

        # Must be the same value the instance passes, so the availability
        # check exercises the real parameter shape (nil without Bundler).
        def default_ignored_path
          return nil unless defined?(Bundler)

          Bundler.bundle_path.to_s
        rescue StandardError
          nil
        end

        def load_ddcov_class!
          require NATIVE_REQUIRE_PATH
          Object.const_get(DDCOV_CONST)
        end

        def build_instance(root:, ignored_path:, use_allocation_tracing:)
          load_ddcov_class!.new(
            root: root,
            ignored_path: ignored_path,
            threading_mode: :multi,
            use_allocation_tracing: use_allocation_tracing
          )
        end

        def reset_memoization!
          @probe = nil
        end

        private

        # Memoizes one probe result per parameter: nil when ddcov works, the
        # exception that broke it otherwise. Keeping "did it work" and "why
        # not" in a single entry means the two can never disagree.
        def probe(use_allocation_tracing)
          @probe ||= {}
          return @probe[use_allocation_tracing] if @probe.key?(use_allocation_tracing)

          @probe[use_allocation_tracing] = begin
            build_instance(root: Paths.repo_root, ignored_path: default_ignored_path,
                           use_allocation_tracing: use_allocation_tracing)
              .tap(&:start).stop
            nil
          rescue LoadError, StandardError => e
            e
          end
        end
      end

      def initialize(config)
        @ddcov = self.class.build_instance(
          root: Paths.repo_root,
          ignored_path: self.class.default_ignored_path,
          use_allocation_tracing: self.class.allocation_tracing?(config)
        )
      end

      def start
        @ddcov.start
      end

      def stop
        @ddcov.stop
      end

      def name
        "ddcov"
      end
    end
  end
end
