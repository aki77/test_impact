# frozen_string_literal: true

module TestImpact
  # The single source of pattern matching semantics for the config keys that
  # take patterns. global_files, always_run and ignore are pure globs;
  # collector.ignored_paths also accepts a plain path prefix (see
  # prefix_or_glob_match?).
  module PathMatcher
    # FNM_PATHNAME is required for "**" to match across directory levels.
    # FNM_DOTMATCH lets "**/*.yml" pick up dotfiles such as ".rubocop.yml".
    FLAGS = File::FNM_PATHNAME | File::FNM_EXTGLOB | File::FNM_DOTMATCH

    # Glob metacharacters; a pattern without any of them is a plain literal.
    GLOB_CHARS = /[*?\[\]{}]/

    def self.match?(pattern, path)
      File.fnmatch?(pattern, path, FLAGS)
    end

    def self.any_match?(patterns, path)
      Array(patterns).any? { |pattern| match?(pattern, path) }
    end

    def self.glob?(pattern)
      GLOB_CHARS.match?(pattern)
    end

    # collector.ignored_paths predates glob support, so a pattern without
    # metacharacters keeps its original "path prefix" meaning: the default
    # 'vendor/' would match nothing as a glob.
    def self.prefix_or_glob_match?(pattern, path)
      glob?(pattern) ? match?(pattern, path) : path.start_with?(pattern)
    end
  end
end
