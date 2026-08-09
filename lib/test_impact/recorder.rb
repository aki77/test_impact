# frozen_string_literal: true

require 'fileutils'
require 'securerandom'
require 'socket'

require 'test_impact/paths'
require 'test_impact/git'
require 'test_impact/map'
require 'test_impact/map_serializer'

module TestImpact
  class Recorder
    DEFAULT_PART_DIR = 'tmp/test_impact'

    attr_reader :backend, :config, :index, :known_spec_files

    def initialize(backend:, config:)
      @backend = backend
      @config = config
      @index = {}
      @known_spec_files = Set.new
      @written = false
      @ignored_paths = Array(config.collector['ignored_paths'])
    end

    def start_example
      backend.start
    end

    def finish_example(spec_abs_path)
      covered = backend.stop || {}
      spec_rel = spec_abs_path && Paths.relative(spec_abs_path)
      return unless inside_repo?(spec_rel)

      covered.each_key do |abs|
        rel = Paths.relative(abs)
        next unless inside_repo?(rel)
        next if spec_file?(rel, spec_rel)
        next if ignored?(rel)

        (@index[rel] ||= Set.new) << spec_rel
      end
    end

    def record_known_spec_files(paths)
      Array(paths).each do |path|
        rel = Paths.relative(path)
        next unless inside_repo?(rel)

        @known_spec_files << rel
      end
    end

    def write_part(dir = ENV['TEST_IMPACT_PART_DIR'] || DEFAULT_PART_DIR)
      return if @written

      FileUtils.mkdir_p(dir)

      # commit_sha is a hard requirement for the plan side: Planner treats a
      # map whose commit is no longer reachable from the base ref as stale
      # (force-push detection). branch is informational (info command).
      git = Git.new
      map = Map.build(
        commit_sha: git.head_sha,
        branch: git.head_branch,
        collector: collector_metadata,
        known_spec_files: @known_spec_files,
        index: @index
      )

      path = File.join(dir, part_filename)
      MapSerializer.dump(map, path)
      # Only flip after a successful write so the at_exit fallback can retry
      # when the after(:suite) attempt fails midway.
      @written = true
      path
    end

    private

    def collector_metadata
      {
        'backend' => backend.name,
        'allocation_tracing' => config.collector['allocation_tracing'] ? true : false,
      }
    end

    def part_filename
      "part-#{Process.pid}-#{Socket.gethostname}-#{SecureRandom.hex(4)}.json.gz"
    end

    def inside_repo?(rel)
      !rel.nil? && !rel.start_with?('..')
    end

    def ignored?(rel)
      @ignored_paths.any? { |prefix| rel.start_with?(prefix) }
    end

    # spec/ files are intentionally never indexed as sources; Planner relies on
    # this contract (changed specs run themselves, other spec/ files fall back).
    def spec_file?(rel, spec_rel)
      rel == spec_rel || rel.start_with?('spec/')
    end
  end
end
