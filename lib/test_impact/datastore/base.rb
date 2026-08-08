# frozen_string_literal: true

module TestImpact
  module Datastore
    class Base
      # Returns the stored gzip bytes (String), or nil if not found.
      def read
        raise NotImplementedError
      end

      # Writes the given gzip bytes (String). Returns true when the bytes were
      # persisted to the datastore itself, or the local path (String) where
      # they were staged when a separate step must complete the upload
      # (e.g. artifact://).
      def write(bytes)
        raise NotImplementedError
      end
    end
  end
end
