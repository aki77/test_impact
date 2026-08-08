# frozen_string_literal: true

require "fileutils"

module TestImpact
  module Datastore
    class Local < Base
      DEFAULT_FILENAME = "map.json.gz"

      def initialize(path)
        @path = resolve_path(path)
      end

      def read
        return nil unless File.exist?(@path)

        File.binread(@path)
      end

      def write(bytes)
        FileUtils.mkdir_p(File.dirname(@path))
        File.binwrite(@path, bytes)
        true
      end

      private

      def resolve_path(path)
        path.end_with?(".gz") ? path : File.join(path, DEFAULT_FILENAME)
      end
    end
  end
end
