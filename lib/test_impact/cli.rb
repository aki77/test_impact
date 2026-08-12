# frozen_string_literal: true

require 'thor'
require 'fileutils'
require 'json'
require 'zlib'

module TestImpact
  # `test-impact` command line entry point: merges per-process coverage parts
  # into a single map, and plans which specs a diff requires.
  # Thor subcommands must live in one class to share its DSL and options, so
  # splitting merge/info/plan out would break the command definitions.
  class CLI < Thor # rubocop:disable Metrics/ClassLength
    # Any unreadable map (schema mismatch, malformed payload, truncated gzip,
    # corrupt JSON) must degrade to "no map" so plan falls back to a full run.
    MAP_LOAD_ERRORS = [
      TestImpact::SchemaVersionError, TestImpact::MapFormatError, Zlib::Error, JSON::ParserError
    ].freeze

    def self.exit_on_failure?
      true
    end

    desc 'merge', 'Merge part-*.json.gz coverage maps into a single map'
    method_option :input, type: :string, default: 'tmp/test_impact', desc: 'Directory containing part-*.json.gz files'
    method_option :output, type: :string, default: '.test_impact/map.json.gz', desc: 'Output path for the merged map'
    def merge
      input_dir = options[:input]
      output_path = options[:output]

      part_paths = Dir.glob(File.join(input_dir, 'part-*.json.gz'))
      die("no part-*.json.gz files found in #{input_dir}") if part_paths.empty?

      merged = merge_parts(load_parts(part_paths), part_paths)

      FileUtils.mkdir_p(File.dirname(output_path))
      MapSerializer.dump(merged, output_path)

      warn_merge_summary(merged, part_paths.size, output_path)
    end

    desc 'info', 'Show summary information about a test impact map'
    method_option :map, type: :string, default: '.test_impact/map.json.gz', desc: 'Path to the map file'
    def info
      map_path = options[:map]

      die("map file not found: #{map_path}") unless File.exist?(map_path)

      begin
        map = MapSerializer.load(map_path)
      rescue *MAP_LOAD_ERRORS => e
        die("could not read map #{map_path}: #{e.message}")
      end

      puts "schema_version: #{map.schema_version}"
      puts "commit_sha: #{map.commit_sha}"
      puts "branch: #{map.branch}"
      puts "generated_at: #{map.generated_at}"
      puts "backend: #{map.collector.fetch('backend', 'unknown')}"
      puts "source_files: #{map.index.keys.size}"
      puts "spec_files: #{map.spec_count}"
      puts "known_spec_files: #{map.known_spec_files.size}"
    end

    desc 'plan', 'Print the spec files impacted by the current diff'
    method_option :map, type: :string, default: '.test_impact/map.json.gz', desc: 'Path to the map file'
    method_option :base, type: :string, desc: 'Base ref to diff against (overrides config and GITHUB_BASE_REF)'
    method_option :format, type: :string, default: 'lines', enum: %w[lines json], desc: 'Output format'
    method_option :fallback_to_all_exit_code,
                  type: :numeric,
                  default: 10,
                  desc: 'Exit code used for lines format when mode is all'
    method_option :include_uncommitted,
                  type: :boolean,
                  default: false,
                  desc: 'Also consider staged, unstaged and untracked working tree changes'
    def plan
      map_path = options[:map]
      config = Config.load
      map = load_map_or_nil(map_path)

      base = options.fetch(:base, normalized_github_base_ref) || config.base
      result = Planner.new(map:, config:).plan(base:, include_uncommitted: options[:include_uncommitted])

      warn "mode: #{result.mode}"
      warn "reason: #{result.reason}" if result.reason
      warn "spec_files: #{result.spec_files.size}"

      if options[:format] == 'json'
        print_plan_json(result)
      else
        print_plan_lines(result)
      end
    end

    private

    def load_parts(part_paths)
      part_paths.map do |path|
        MapSerializer.load(path)
      rescue *MAP_LOAD_ERRORS => e
        die("could not read part #{path}: #{e.message}")
      end
    end

    def merge_parts(maps, part_paths)
      base_commit_sha = maps.first.commit_sha

      maps[1..].each_with_index.reduce(maps[0]) do |merged, (map, idx)|
        if map.commit_sha != base_commit_sha
          warn "warning: commit_sha mismatch in #{part_paths[idx + 1]} (#{map.commit_sha} != #{base_commit_sha})"
        end
        merged.merge(map)
      end
    end

    def warn_merge_summary(merged, part_count, output_path)
      warn "merged #{part_count} part(s) into #{output_path}"
      warn "source files: #{merged.index.keys.size}, specs: #{merged.spec_count}, " \
           "known_spec_files: #{merged.known_spec_files.size}"
    end

    def print_plan_json(result)
      puts JSON.generate({ 'mode' => result.mode.to_s, 'spec_files' => result.spec_files, 'reason' => result.reason })
      exit(0)
    end

    def print_plan_lines(result)
      exit(options[:fallback_to_all_exit_code]) if result.mode == :all

      puts result.spec_files.join("\n") unless result.spec_files.empty?
      exit(0)
    end

    def die(message)
      warn "error: #{message}"
      exit(1)
    end

    def load_map_or_nil(map_path)
      return nil unless File.exist?(map_path)

      begin
        MapSerializer.load(map_path)
      rescue *MAP_LOAD_ERRORS => e
        warn "warning: could not read map #{map_path}: #{e.message}"
        nil
      end
    end

    def normalized_github_base_ref
      ref = ENV.fetch('GITHUB_BASE_REF', nil)
      ref.nil? || ref.empty? ? nil : "origin/#{ref}"
    end
  end
end
