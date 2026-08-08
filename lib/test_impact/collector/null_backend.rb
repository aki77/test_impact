# frozen_string_literal: true

module TestImpact
  module Collector
    class NullBackend
      def start
        nil
      end

      def stop
        {}
      end

      def name
        "null"
      end
    end
  end
end
