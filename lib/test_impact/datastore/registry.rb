# frozen_string_literal: true

require "uri"

module TestImpact
  module Datastore
    module Registry
      class << self
        def build(url)
          uri = begin
            URI.parse(url)
          rescue URI::InvalidURIError => e
            raise DatastoreError, "invalid datastore url #{url.inspect}: #{e.message}"
          end

          case uri.scheme
          when "local", "file"
            Local.new("#{uri.host}#{uri.path}")
          when "artifact"
            owner, repo, name = split_path(uri)
            Artifact.new(owner: owner, repo: repo, name: name || Artifact::DEFAULT_NAME)
          when "branch", "github"
            build_branch(uri)
          else
            raise DatastoreError, "unknown datastore scheme: #{uri.scheme.inspect} (url: #{url.inspect})"
          end
        end

        private

        # Splits scheme://owner/repo[/rest] into [owner, repo, rest].
        # rest is nil when absent or empty (e.g. a trailing slash).
        def split_path(uri)
          owner = uri.host
          repo, rest = uri.path.to_s.sub(%r{\A/}, "").split("/", 2)

          raise DatastoreError, "invalid datastore url (missing owner/repo): #{uri}" if owner.nil? || repo.nil? || repo.empty?

          [owner, repo, presence(rest)]
        end

        # Grammar: branch://owner/repo[/path][@branch]. The branch is split off
        # first (everything after the first "@") so branch names containing "/"
        # (feature/x, release/1.0) parse correctly.
        def build_branch(uri)
          owner = uri.host
          remainder = uri.path.to_s.sub(%r{\A/}, "")
          repo_and_path, branch = remainder.split("@", 2)
          repo, path = repo_and_path.to_s.split("/", 2)

          raise DatastoreError, "invalid datastore url (missing owner/repo): #{uri}" if owner.nil? || repo.nil? || repo.empty?

          Branch.new(
            owner: owner,
            repo: repo,
            branch: presence(branch) || Branch::DEFAULT_BRANCH,
            path: presence(path) || Branch::DEFAULT_PATH
          )
        end

        def presence(value)
          value unless value.nil? || value.empty?
        end
      end
    end
  end
end
