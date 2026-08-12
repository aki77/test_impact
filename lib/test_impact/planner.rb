# frozen_string_literal: true

module TestImpact
  # Classifies the files changed since the merge-base and turns them into a
  # PlanResult, degrading to a full run whenever the map cannot be trusted.
  # The classify_* methods all serve the single job of deciding what a changed
  # file implies, so splitting them out would scatter one decision across classes.
  class Planner # rubocop:disable Metrics/ClassLength
    IGNORABLE_EXTENSIONS = ['.md', '.txt', '.adoc'].freeze
    # Ruby sources and view templates. ActionView compiles templates under
    # their absolute path, so DDCov records them like any other source file.
    TRACKED_EXTENSIONS = ['.rb', '.erb', '.haml', '.slim', '.jbuilder'].freeze

    def initialize(map:, config:, git: Git.new)
      @map = map
      @config = config
      @git = git
    end

    def plan(base: nil, include_uncommitted: false)
      changed = changed_files_or_reason(base || config.base, include_uncommitted:)
      return PlanResult.all(changed) if changed.is_a?(String)

      spec_files = Set.new
      all_reason = nil

      changed.each do |change|
        all_reason = classify(change, spec_files)
        break if all_reason
      end

      return PlanResult.all(all_reason) if all_reason

      apply_always_run(spec_files)
      spec_files.select! { |path| File.exist?(Paths.absolute(path)) }

      PlanResult.partial(spec_files)
    end

    private

    attr_reader :map, :config, :git

    # Returns the changed files for base_ref, or a String reason when the diff
    # cannot be trusted and the caller must degrade to a full run.
    def changed_files_or_reason(base_ref, include_uncommitted:)
      return 'no map available or backend invalid' if invalid_map?

      stale_reason = staleness_reason(base_ref)
      return stale_reason if stale_reason

      merge_base_sha = git.merge_base(base_ref)
      return 'could not compute merge-base (shallow clone? try fetch-depth: 0 in checkout)' unless merge_base_sha

      git.changed_files(merge_base_sha, include_uncommitted:) ||
        "could not compute git diff against #{merge_base_sha}"
    end

    def invalid_map?
      map.nil? || map.empty? || !map.valid_backend?
    end

    def staleness_reason(base_ref)
      if map.generated_at < (Time.now - (config.max_age_days * 86_400))
        return "map is older than max_age_days (#{config.max_age_days})"
      end

      unless git.in_history?(map.commit_sha, base_ref)
        return "map commit_sha #{map.commit_sha} not found in #{base_ref} history"
      end

      nil
    end

    # Returns an "all" reason string if this change forces a full run, otherwise nil
    # (and mutates spec_files as a side effect).
    def classify(change, spec_files)
      path = change[:path]

      global_reason = global_change_reason(change)
      return global_reason if global_reason

      return classify_as_spec(change, spec_files) if spec_file?(path)

      # A file renamed away from a tracked path still carries its old
      # coverage, so the old extension counts too — its dependent specs must
      # not be silently dropped.
      if tracked_file?(path) || (change[:old_path] && tracked_file?(change[:old_path]))
        return classify_tracked(change, spec_files)
      end

      classify_other(change)
    end

    # A rename away from a global location is still a change to that
    # global file — it must not slip past the safeguard.
    def global_change_reason(change)
      return "global file changed: #{change[:path]}" if global_file?(change[:path])
      return "global file changed: #{change[:old_path]}" if change[:old_path] && global_file?(change[:old_path])

      nil
    end

    # A source file renamed into a spec path still carries its old coverage —
    # pull its dependents (or fall back) in addition to scheduling the new
    # spec itself.
    def classify_as_spec(change, spec_files)
      classify_spec(change, spec_files)

      old_path = change[:old_path]
      return nil unless old_path && tracked_file?(old_path) && !spec_file?(old_path)

      classify_renamed_tracked(change, spec_files)
    end

    # Spec files are never indexed as coverage sources (Recorder skips spec/),
    # so a changed spec only schedules itself. Non-spec helpers under spec/
    # (support files etc.) fall through to the uncovered-file fallback instead.
    def classify_spec(change, spec_files)
      case change[:status]
      when 'A', 'M', 'R'
        spec_files << change[:path]
      when 'D'
        # excluded: do nothing
      end

      nil
    end

    def classify_tracked(change, spec_files)
      case change[:status]
      when 'R'
        classify_renamed_tracked(change, spec_files)
      else # "A", "M", "D" — an uncovered file always forces a full run
        pull_covered_specs_or_fallback(change[:path], spec_files)
      end
    end

    # The map predates the rename, so the old path carries the known
    # dependents; a covered old path must not force a full run just because
    # the new name is absent from the map.
    def classify_renamed_tracked(change, spec_files)
      covered_old = map&.covered?(change[:old_path])
      spec_files.merge(map.specs_for(change[:old_path])) if covered_old

      if map&.covered?(change[:path])
        spec_files.merge(map.specs_for(change[:path]))
        nil
      elsif covered_old
        nil
      else
        "uncovered file changed: #{change[:path]}"
      end
    end

    def pull_covered_specs_or_fallback(path, spec_files)
      if map&.covered?(path)
        spec_files.merge(map.specs_for(path))
        nil
      else
        "uncovered file changed: #{path}"
      end
    end

    def classify_other(change)
      path = change[:path]
      ext = File.extname(path)

      return nil if IGNORABLE_EXTENSIONS.include?(ext)

      "unknown file type changed: #{path}"
    end

    def apply_always_run(spec_files)
      return if config.always_run.empty?

      candidates = Set.new(spec_files)
      candidates.merge(map.known_spec_files) if map

      candidates.each do |spec_path|
        next unless config.always_run.any? { |pattern| fnmatch?(pattern, spec_path) }
        next unless File.exist?(Paths.absolute(spec_path))

        spec_files << spec_path
      end
    end

    def global_file?(path)
      config.global_files.any? { |pattern| fnmatch?(pattern, path) }
    end

    def spec_file?(path)
      path.end_with?('_spec.rb') && path.start_with?('spec/')
    end

    # A file that can appear as a key in the coverage map.
    def tracked_file?(path)
      TRACKED_EXTENSIONS.include?(File.extname(path))
    end

    def fnmatch?(pattern, path)
      # FNM_PATHNAME is required for "**" to match across directory levels.
      File.fnmatch?(pattern, path, File::FNM_PATHNAME | File::FNM_EXTGLOB)
    end
  end
end
