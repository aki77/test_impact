# frozen_string_literal: true

require "zip"
require "stringio"
require "fileutils"

module TestImpact
  module Datastore
    class Artifact < Base
      DEFAULT_NAME = "test-impact-map"
      FALLBACK_PATH = ".test_impact/map.json.gz"

      def initialize(owner:, repo:, name: DEFAULT_NAME, client: nil)
        @owner = owner
        @repo = repo
        @name = name
        @client = client
      end

      def read
        artifact = latest_artifact
        return nil unless artifact

        location = client.get_redirect_location("repos/#{@owner}/#{@repo}/actions/artifacts/#{artifact["id"]}/zip")
        return nil unless location

        zip_bytes = client.get_raw(location)
        extract_map(zip_bytes)
      end

      def write(bytes)
        FileUtils.mkdir_p(File.dirname(FALLBACK_PATH))
        File.binwrite(FALLBACK_PATH, bytes)

        warn "test_impact: wrote map to #{FALLBACK_PATH}; upload it via actions/upload-artifact with name: #{@name}"
        FALLBACK_PATH
      end

      private

      # Lazy: #write never touches the GitHub API, so it must work without a
      # token; only #read needs an authenticated client.
      def client
        @client ||= GithubClient.new
      end

      def latest_artifact
        response = client.get_json("repos/#{@owner}/#{@repo}/actions/artifacts", name: @name, per_page: 100)
        artifacts = response && response["artifacts"] || []
        artifacts
          .select { |a| a["expired"] == false }
          .max_by { |a| a["created_at"] }
      end

      # An artifact that exists but holds no map is a broken artifact, not a
      # missing one — raise instead of blending it into the "no map" nil.
      def extract_map(zip_bytes)
        content = nil

        begin
          Zip::File.open_buffer(StringIO.new(zip_bytes)) do |zip|
            entry = zip.glob("map.json.gz").first || zip.entries.find { |e| e.name.end_with?(".json.gz") }
            content = entry&.get_input_stream&.read
          end
        rescue Zip::Error => e
          raise DatastoreError, "artifact #{@name} is not a valid zip: #{e.message}"
        end

        raise DatastoreError, "artifact #{@name} did not contain a .json.gz map entry" if content.nil?

        content
      end
    end
  end
end
