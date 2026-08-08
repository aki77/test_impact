# frozen_string_literal: true

require "base64"

module TestImpact
  module Datastore
    class Branch < Base
      DEFAULT_BRANCH = "test-impact-data"
      DEFAULT_PATH = "map.json.gz"
      CONFLICT_CODES = [409, 422].freeze

      def initialize(owner:, repo:, branch: DEFAULT_BRANCH, path: DEFAULT_PATH, client: GithubClient.new)
        @owner = owner
        @repo = repo
        @branch = branch
        @path = path
        @client = client
      end

      def read
        status, body = get_content
        return nil if status == 404

        raise DatastoreError, api_error_message(status, body) unless status == 200

        content = body["content"]
        # The Contents API omits "content" for files larger than 1MB;
        # fetch those through the Blobs API instead.
        return read_blob(body["sha"]) if content.nil? || content.empty?

        Base64.decode64(content)
      end

      def write(bytes)
        status = body = nil

        2.times do
          status, body = put_content(bytes, current_sha)
          return true if status == 200 || status == 201
          break unless CONFLICT_CODES.include?(status)
        end

        raise DatastoreError, api_error_message(status, body)
      end

      private

      def current_sha
        status, body = get_content
        return nil if status == 404
        raise DatastoreError, api_error_message(status, body) unless status == 200

        body["sha"]
      end

      def get_content
        @client.get_json_with_status("repos/#{@owner}/#{@repo}/contents/#{@path}", ref: @branch)
      end

      def read_blob(sha)
        raise DatastoreError, "GitHub API error: contents response had no content and no sha" if sha.nil? || sha.empty?

        status, body = @client.get_json_with_status("repos/#{@owner}/#{@repo}/git/blobs/#{sha}")
        raise DatastoreError, api_error_message(status, body) unless status == 200

        Base64.decode64(body["content"])
      end

      def put_content(bytes, sha)
        body = {
          message: commit_message,
          content: Base64.strict_encode64(bytes),
          branch: @branch
        }
        body[:sha] = sha if sha

        @client.put_json_with_status("repos/#{@owner}/#{@repo}/contents/#{@path}", body)
      end

      def api_error_message(status, body)
        message = body && body["message"]

        if status == 404 && message&.match?(/no commit found|branch not found/i)
          "GitHub API error: 404 #{message} (branch #{@branch.inspect} may not exist on #{@owner}/#{@repo}; " \
            "create it first, e.g. `git switch --orphan #{@branch} && git commit --allow-empty -m init && " \
            "git push origin #{@branch}`)"
        else
          "GitHub API error: #{status} #{message}"
        end
      end

      def commit_message
        commit_sha = ENV["GITHUB_SHA"]
        ref = commit_sha ? commit_sha[0, 7] : Time.now.utc.iso8601
        "Update test impact map (#{ref})"
      end
    end
  end
end
