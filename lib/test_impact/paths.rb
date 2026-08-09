# frozen_string_literal: true

require 'open3'
require 'pathname'

module TestImpact
  # Resolves the repository root and converts between absolute paths and the
  # repo-relative paths the map is keyed by.
  module Paths
    class << self
      def repo_root
        @repo_root ||=
          begin
            stdout, status = Open3.capture2('git', 'rev-parse', '--show-toplevel')
            status.success? ? stdout.strip : Dir.pwd
          rescue StandardError
            Dir.pwd
          end
      end

      def relative(abs_path)
        Pathname.new(abs_path).relative_path_from(root_pathname).to_s
      end

      def absolute(rel_path)
        File.expand_path(rel_path, repo_root)
      end

      private

      # Cached per repo_root value so stubs and re-memoization stay consistent.
      def root_pathname
        root = repo_root
        @root_pathname = Pathname.new(root) if @root_pathname.nil? || @root_pathname.to_s != root
        @root_pathname
      end
    end
  end
end
