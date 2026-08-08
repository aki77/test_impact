# frozen_string_literal: true

require "thor"
require "fileutils"
require "json"
require "zlib"

module TestImpact
  class CLI < Thor
    def self.exit_on_failure?
      true
    end

    desc "merge", "Merge part-*.json.gz coverage maps into a single map"
    method_option :input, type: :string, default: "tmp/test_impact", desc: "Directory containing part-*.json.gz files"
    method_option :output, type: :string, default: ".test_impact/map.json.gz", desc: "Output path for the merged map"
    def merge
      input_dir = options[:input]
      output_path = options[:output]

      part_paths = Dir.glob(File.join(input_dir, "part-*.json.gz")).sort
      die("no part-*.json.gz files found in #{input_dir}") if part_paths.empty?

      maps = part_paths.map do |path|
        MapSerializer.load(path)
      rescue *MAP_LOAD_ERRORS => e
        die("could not read part #{path}: #{e.message}")
      end

      base_commit_sha = maps.first.commit_sha
      merged = maps[0]
      maps[1..].each_with_index do |map, idx|
        if map.commit_sha != base_commit_sha
          $stderr.puts "warning: commit_sha mismatch in #{part_paths[idx + 1]} (#{map.commit_sha} != #{base_commit_sha})"
        end
        merged = merged.merge(map)
      end

      FileUtils.mkdir_p(File.dirname(output_path))
      MapSerializer.dump(merged, output_path)

      $stderr.puts "merged #{part_paths.size} part(s) into #{output_path}"
      $stderr.puts "source files: #{merged.index.keys.size}, specs: #{merged.spec_count}, known_spec_files: #{merged.known_spec_files.size}"
    end

    desc "info", "Show summary information about a test impact map"
    method_option :map, type: :string, default: ".test_impact/map.json.gz", desc: "Path to the map file"
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
      puts "backend: #{map.collector["backend"] || "unknown"}"
      puts "source_files: #{map.index.keys.size}"
      puts "spec_files: #{map.spec_count}"
      puts "known_spec_files: #{map.known_spec_files.size}"
    end

    desc "plan", "Print the spec files impacted by the current diff"
    method_option :map, type: :string, default: ".test_impact/map.json.gz", desc: "Path to the map file"
    method_option :base, type: :string, desc: "Base ref to diff against (overrides config and GITHUB_BASE_REF)"
    method_option :format, type: :string, default: "lines", enum: %w[lines json], desc: "Output format"
    method_option :fallback_to_all_exit_code, type: :numeric, default: 10,
                                               desc: "Exit code used for lines format when mode is all"
    def plan
      map_path = options[:map]
      config = Config.load
      map = load_map_or_nil(map_path)

      base = options[:base] || normalized_github_base_ref || config.base
      result = Planner.new(map: map, config: config).plan(base: base)

      $stderr.puts "mode: #{result.mode}"
      $stderr.puts "reason: #{result.reason}" if result.reason
      $stderr.puts "spec_files: #{result.spec_files.size}"

      case options[:format]
      when "json"
        puts JSON.generate({ "mode" => result.mode.to_s, "spec_files" => result.spec_files, "reason" => result.reason })
        exit(0)
      else
        if result.mode == :all
          exit(options[:fallback_to_all_exit_code])
        else
          puts result.spec_files.join("\n") unless result.spec_files.empty?
          exit(0)
        end
      end
    end

    private

    def die(message)
      $stderr.puts "error: #{message}"
      exit(1)
    end

    # Any unreadable map (schema mismatch, malformed payload, truncated gzip,
    # corrupt JSON) must degrade to "no map" so plan falls back to a full run.
    MAP_LOAD_ERRORS = [
      TestImpact::SchemaVersionError, TestImpact::MapFormatError, Zlib::Error, JSON::ParserError
    ].freeze

    def load_map_or_nil(map_path)
      return nil unless File.exist?(map_path)

      begin
        MapSerializer.load(map_path)
      rescue *MAP_LOAD_ERRORS => e
        $stderr.puts "warning: could not read map #{map_path}: #{e.message}"
        nil
      end
    end

    def normalized_github_base_ref
      ref = ENV["GITHUB_BASE_REF"]
      ref.nil? || ref.empty? ? nil : "origin/#{ref}"
    end
  end
end
