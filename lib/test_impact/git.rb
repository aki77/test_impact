# frozen_string_literal: true

require 'json'
require 'open3'

module TestImpact
  # Thin wrapper over the git commands planning needs: merge-base lookup,
  # name-status diffs (rename/copy aware), and reachability checks.
  class Git
    def initialize(repo_root: Paths.repo_root)
      @repo_root = repo_root
    end

    def merge_base(base_ref)
      stdout, status = run('merge-base', base_ref, 'HEAD')
      status.success? ? stdout.strip : nil
    end

    # Returns nil when the diff itself fails, so callers can distinguish
    # "no changes" ([]) from "could not compute the diff". Omitting the
    # trailing HEAD diffs merge_base_sha against the working tree
    # (staged + unstaged combined) instead of against the last commit.
    def changed_files(merge_base_sha, include_uncommitted: false)
      diff_args = ['diff', '--name-status', '-M', '-C', merge_base_sha]
      diff_args << 'HEAD' unless include_uncommitted

      stdout, status = run(*diff_args)
      return nil unless status.success?

      diffed = stdout.each_line.filter_map { |line| parse_diff_line(line) }
      return diffed unless include_uncommitted

      merge_untracked(diffed)
    end

    # True when sha is reachable from ref. A mere `cat-file -e` object check
    # would also accept dangling objects left behind by a force-push.
    def in_history?(sha, ref)
      _, status = run('merge-base', '--is-ancestor', sha, ref)
      status.success?
    end

    # On pull_request events actions/checkout checks out the synthetic
    # refs/pull/N/merge commit, which exists in no branch history — a map
    # recorded under it would always look stale to Planner#in_history?.
    # The event payload carries the real head commit, so prefer it there.
    def head_sha
      pull_request_head_sha || rev_parse('HEAD')
    end

    # Detached HEAD (the default actions/checkout state) yields the literal
    # string "HEAD"; only then is CI's branch name a valid substitute.
    # GITHUB_HEAD_REF holds the source branch on pull_request events (where
    # GITHUB_REF_NAME would be the synthetic "N/merge" ref). An empty result
    # means git itself failed — keep it visible as "".
    def head_branch
      name = rev_parse('--abbrev-ref', 'HEAD')
      return name unless name == 'HEAD'

      ci_branch = [ENV.fetch('GITHUB_HEAD_REF', nil), ENV.fetch('GITHUB_REF_NAME', nil)].find { |v| v && !v.empty? }
      ci_branch || name
    end

    private

    def rev_parse(*)
      stdout, status = run('rev-parse', *)
      status.success? ? stdout.strip : ''
    rescue StandardError
      ''
    end

    # Only pull_request-shaped events carry pull_request.head.sha; on push
    # GITHUB_EVENT_PATH is still set but the key is absent, so this returns
    # nil and the plain HEAD lookup stands. dig raises TypeError when an
    # intermediate value is not a Hash, so the rescue must cover it too.
    def pull_request_head_sha
      path = ENV.fetch('GITHUB_EVENT_PATH', nil)
      return nil if path.nil? || path.empty? || !File.file?(path)

      sha = JSON.parse(File.read(path)).dig('pull_request', 'head', 'sha')
      sha if sha.is_a?(String) && !sha.empty?
    rescue StandardError
      nil
    end

    # Untracked files are new by definition, so they map straight to 'A'
    # and cannot collide with the diff output.
    def merge_untracked(diffed)
      untracked = untracked_files
      return nil unless untracked

      diffed + untracked.map { |path| { status: 'A', path: } }
    end

    def untracked_files
      stdout, status = run('ls-files', '--others', '--exclude-standard', '-z')
      return nil unless status.success?

      stdout.split("\0").reject(&:empty?)
    end

    def parse_diff_line(line)
      fields = line.chomp.split("\t")
      return nil if fields.empty?

      raw_status, *paths = fields

      case raw_status[0]
      when 'R'
        { status: 'R', path: paths[1], old_path: paths[0] }
      when 'C'
        # Copy lines list source then destination; only the destination is new.
        { status: 'A', path: paths[1] }
      else
        { status: raw_status[0], path: paths[0] }
      end
    end

    def run(*)
      stdout, _stderr, status = Open3.capture3('git', '-C', @repo_root, *)
      [stdout, status]
    end
  end
end
