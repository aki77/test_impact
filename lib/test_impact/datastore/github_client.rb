# frozen_string_literal: true

require "net/http"
require "json"
require "uri"

module TestImpact
  module Datastore
    class GithubClient
      USER_AGENT = "test_impact"
      MAX_REDIRECTS = 5

      def initialize(token: self.class.default_token)
        raise DatastoreError, "no GitHub token found (set GITHUB_TOKEN or TEST_IMPACT_GITHUB_TOKEN)" if token.nil? || token.empty?

        @token = token
      end

      # Skips empty strings so an unset-but-present GITHUB_TOKEN (common in CI)
      # still falls back to TEST_IMPACT_GITHUB_TOKEN.
      def self.default_token
        [ENV["GITHUB_TOKEN"], ENV["TEST_IMPACT_GITHUB_TOKEN"]].find { |t| t && !t.empty? }
      end

      def api_base
        ENV["GITHUB_API_URL"] || "https://api.github.com"
      end

      # Collapses 404 to nil and raises on other errors.
      def get_json(path, params = {})
        status, body = get_json_with_status(path, params)
        return nil if status == 404
        raise DatastoreError, "GitHub API error: #{status} #{body && body["message"]}" unless (200..299).cover?(status)

        body
      end

      # Returns [status_code, parsed_body_or_nil] so callers can distinguish
      # "not found" reasons and handle conflicts themselves.
      def get_json_with_status(path, params = {})
        uri = build_uri(path, params)
        with_status(request(Net::HTTP::Get.new(uri), uri))
      end

      def put_json_with_status(path, body)
        uri = build_uri(path)
        req = Net::HTTP::Put.new(uri)
        req.body = JSON.generate(body)

        with_status(request(req, uri))
      end

      # Returns the Location header of a redirect response, nil on 404,
      # and raises on any other status (auth failures, 5xx, ...).
      def get_redirect_location(path)
        uri = build_uri(path)
        response = request(Net::HTTP::Get.new(uri), uri, follow_redirects: false)
        return response["location"] if response.is_a?(Net::HTTPRedirection)
        return nil if response.code.to_i == 404

        raise DatastoreError, "GitHub API error: #{response.code} #{response.body}"
      end

      # Fetches the raw bytes at url, following redirects (even to non-api.github.com hosts, without auth).
      def get_raw(url)
        uri = URI(url)

        (MAX_REDIRECTS + 1).times do
          req = Net::HTTP::Get.new(uri)
          req["User-Agent"] = USER_AGENT
          req["Authorization"] = "Bearer #{@token}" if api_host?(uri)

          response = perform(uri, req)

          case response
          when Net::HTTPRedirection
            uri = URI(response["location"])
          when Net::HTTPSuccess
            return response.body
          else
            raise DatastoreError, "GitHub API error: #{response.code} #{response.body}"
          end
        end

        raise DatastoreError, "too many redirects (more than #{MAX_REDIRECTS}) fetching #{url}"
      end

      private

      # Plain concatenation instead of URI.join: a GHES api base like
      # "https://ghe.example.com/api/v3" has a path segment that URI.join
      # would silently drop from relative references.
      def build_uri(path, params = {})
        uri = URI.parse("#{api_base.sub(%r{/+\z}, "")}/#{path.sub(%r{\A/+}, "")}")
        uri.query = URI.encode_www_form(params) unless params.empty?
        uri
      end

      def with_status(response)
        body = response.body && !response.body.empty? ? JSON.parse(response.body) : nil
        [response.code.to_i, body]
      rescue JSON::ParserError
        # Proxies and rate limiters answer with HTML error pages; keep the
        # DatastoreError contract instead of leaking a raw parse error.
        raise DatastoreError, "GitHub API returned a non-JSON response (status #{response.code})"
      end

      def request(req, uri, follow_redirects: true, redirects_left: MAX_REDIRECTS)
        req["Accept"] = "application/vnd.github+json"
        req["User-Agent"] = USER_AGENT
        # Never forward the token to hosts other than the API host (e.g. on redirect).
        req["Authorization"] = "Bearer #{@token}" if api_host?(uri)
        req["Content-Type"] = "application/json" if req.request_body_permitted? && req.body

        response = perform(uri, req)

        if follow_redirects && response.is_a?(Net::HTTPRedirection)
          # Following a redirect replays the request as a GET, which would turn
          # a redirected write into a silent no-op reported as success.
          unless req.is_a?(Net::HTTP::Get)
            raise DatastoreError,
                  "unexpected redirect (#{response.code}) for #{req.method} #{uri} (repository moved or renamed?)"
          end
          raise DatastoreError, "too many redirects (more than #{MAX_REDIRECTS}) requesting #{uri}" if redirects_left <= 0

          location = URI(response["location"])
          return request(Net::HTTP::Get.new(location), location, redirects_left: redirects_left - 1)
        end

        response
      end

      def api_host?(uri)
        uri.host == URI(api_base).host
      end

      def perform(uri, req)
        Net::HTTP.start(uri.host, uri.port, use_ssl: uri.scheme == "https") do |http|
          http.request(req)
        end
      end
    end
  end
end
