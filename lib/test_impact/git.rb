# frozen_string_literal: true

require 'open3'

module TestImpact
  class Git
    def initialize(repo_root: Paths.repo_root)
      @repo_root = repo_root
    end

    def merge_base(base_ref)
      stdout, status = run('merge-base', base_ref, 'HEAD')
      status.success? ? stdout.strip : nil
    end

    # Returns nil when the diff itself fails, so callers can distinguish
    # "no changes" ([]) from "could not compute the diff".
    def changed_files(merge_base_sha)
      stdout, status = run('diff', '--name-status', '-M', '-C', merge_base_sha, 'HEAD')
      return nil unless status.success?

      stdout.each_line.filter_map { |line| parse_diff_line(line) }
    end

    # True when sha is reachable from ref. A mere `cat-file -e` object check
    # would also accept dangling objects left behind by a force-push.
    def in_history?(sha, ref)
      _, status = run('merge-base', '--is-ancestor', sha, ref)
      status.success?
    end

    def head_sha
      rev_parse('HEAD')
    end

    # Detached HEAD (the default actions/checkout state) yields the literal
    # string "HEAD"; only then is CI's branch name a valid substitute.
    # GITHUB_HEAD_REF holds the source branch on pull_request events (where
    # GITHUB_REF_NAME would be the synthetic "N/merge" ref). An empty result
    # means git itself failed — keep it visible as "".
    def head_branch
      name = rev_parse('--abbrev-ref', 'HEAD')
      return name unless name == 'HEAD'

      ci_branch = [ENV['GITHUB_HEAD_REF'], ENV['GITHUB_REF_NAME']].find { |v| v && !v.empty? }
      ci_branch || name
    end

    private

    def rev_parse(*args)
      stdout, status = run('rev-parse', *args)
      status.success? ? stdout.strip : ''
    rescue StandardError
      ''
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

    def run(*args)
      stdout, _stderr, status = Open3.capture3('git', '-C', @repo_root, *args)
      [stdout, status]
    end
  end
end
