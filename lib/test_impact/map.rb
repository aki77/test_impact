# frozen_string_literal: true

module TestImpact
  class Map
    SCHEMA_VERSION = 1

    attr_reader :schema_version, :generated_at, :commit_sha, :branch, :collector, :known_spec_files, :index

    def self.build(commit_sha:, branch:, collector:, generated_at: Time.now, known_spec_files: [], index: {})
      new(
        schema_version: SCHEMA_VERSION,
        generated_at:,
        commit_sha:,
        branch:,
        collector:,
        known_spec_files:,
        index:
      )
    end

    def initialize(schema_version:, generated_at:, commit_sha:, branch:, collector:, known_spec_files:, index:)
      # Set.new(nil) silently yields an empty Set; nils and wrong types here
      # are malformed payloads and must raise so MapSerializer degrades them
      # to MapFormatError instead of crashing later in Planner.
      raise TypeError, 'known_spec_files must not be nil' if known_spec_files.nil?
      raise TypeError, 'collector must be a Hash' unless collector.is_a?(Hash)
      raise TypeError, 'commit_sha must be a String' unless commit_sha.is_a?(String)
      raise TypeError, 'branch must be a String' unless branch.is_a?(String)
      raise TypeError, 'generated_at must be a Time' unless generated_at.is_a?(Time)

      @schema_version = schema_version
      @generated_at = generated_at
      @commit_sha = commit_sha
      @branch = branch
      @collector = collector
      @known_spec_files = Set.new(known_spec_files)
      @index =
        index.each_with_object({}) do |(k, v), h|
          raise TypeError, "index value for #{k.inspect} must not be nil" if v.nil?

          h[k] = Set.new(v)
        end
    end

    def commit_sha_mismatch?(other)
      commit_sha != other.commit_sha
    end

    # Metadata (generated_at, commit_sha, branch, collector) always comes from
    # the newer of the two maps, so merge order cannot pair a fresh timestamp
    # with a stale commit_sha.
    def merge(other)
      merged_index = index.each_with_object({}) { |(k, v), h| h[k] = v.dup }
      other.index.each do |k, v|
        merged_index[k] = (merged_index[k] || Set.new) | v
      end

      newer = other.generated_at >= generated_at ? other : self

      self.class.new(
        schema_version: SCHEMA_VERSION,
        generated_at: newer.generated_at,
        commit_sha: newer.commit_sha,
        branch: newer.branch,
        collector: merged_collector(newer:, other:),
        known_spec_files: known_spec_files | other.known_spec_files,
        index: merged_index
      )
    end

    def specs_for(source_path)
      index[source_path] || Set.new
    end

    def covered?(source_path)
      index.key?(source_path)
    end

    def empty?
      index.empty?
    end

    def spec_count
      index.each_value.with_object(Set.new) { |specs, acc| acc.merge(specs) }.size
    end

    def valid_backend?
      collector['backend'] != 'null'
    end

    def ==(other)
      other.is_a?(Map) &&
        schema_version == other.schema_version &&
        generated_at == other.generated_at &&
        commit_sha == other.commit_sha &&
        branch == other.branch &&
        collector == other.collector &&
        known_spec_files == other.known_spec_files &&
        index == other.index
    end
    alias eql? ==

    def hash
      [schema_version, generated_at, commit_sha, branch, collector, known_spec_files, index].hash
    end

    private

    # A "null" backend in any merged part means part of the coverage is missing,
    # so the merged map must stay invalid regardless of merge order.
    def merged_collector(newer:, other:)
      if collector['backend'] == 'null' || other.collector['backend'] == 'null'
        newer.collector.merge('backend' => 'null')
      else
        newer.collector
      end
    end
  end
end
