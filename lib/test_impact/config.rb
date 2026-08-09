# frozen_string_literal: true

require 'yaml'

module TestImpact
  # Settings loaded from .test_impact.yml, with defaults for the base ref,
  # map staleness, always-run specs, global files, and collector options.
  class Config
    DEFAULT_GLOBAL_FILES = [
      'Gemfile',
      'Gemfile.lock',
      '*.gemspec',
      '.ruby-version',
      'Dockerfile',
      'config/**/*',
      'db/schema.rb',
      'db/structure.sql',
      'spec/spec_helper.rb',
      'spec/rails_helper.rb',
      'spec/factories/**/*',
      'spec/fixtures/**/*',
    ].freeze

    DEFAULT_COLLECTOR = {
      'allocation_tracing' => true,
      'ignored_paths' => ['vendor/', 'tmp/'].freeze,
    }.freeze

    attr_reader :base, :max_age_days, :always_run, :global_files, :collector

    def self.load(path = nil)
      path ||= File.join(Paths.repo_root, '.test_impact.yml')
      raw = File.exist?(path) ? (YAML.safe_load_file(path) || {}) : {}
      new(raw)
    end

    def initialize(raw = {})
      raw = raw.transform_keys(&:to_s)

      @base = value_or_default(raw, 'base', 'origin/main')
      @max_age_days = value_or_default(raw, 'max_age_days', 7)
      @always_run = value_or_default(raw, 'always_run', [])
      @global_files = value_or_default(raw, 'global_files', DEFAULT_GLOBAL_FILES.dup)
      @collector = DEFAULT_COLLECTOR.merge(value_or_default(raw, 'collector', {}))
    end

    private

    # Unlike Hash#fetch, treats an explicitly nil value (e.g. a bare
    # "collector:" line in YAML) as absent so defaults still apply.
    def value_or_default(raw, key, default)
      value = raw[key]
      value.nil? ? default : value
    end
  end
end
