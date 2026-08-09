# frozen_string_literal: true

module TestImpact
  module Collector
    # Fallback backend that records nothing. Used when coverage is unavailable
    # and the caller opted out of failing; the resulting map stays invalid so
    # planning degrades to a full run.
    class NullBackend
      def start
        nil
      end

      def stop
        {}
      end

      def name
        'null'
      end
    end
  end
end
