# frozen_string_literal: true

require "webmock/rspec"
require "base64"

RSpec.describe TestImpact::Datastore::Branch do
  let(:branch) do
    described_class.new(owner: "acme", repo: "widgets", client: TestImpact::Datastore::GithubClient.new(token: "tok"))
  end

  describe "#read" do
    it "decodes the base64 content when the file exists" do
      body = { "content" => Base64.strict_encode64("gzipped-bytes"), "sha" => "abc" }
      stub_request(:get, "https://api.github.com/repos/acme/widgets/contents/map.json.gz")
        .with(query: { ref: "test-impact-data" })
        .to_return(status: 200, body: JSON.generate(body))

      expect(branch.read).to eq("gzipped-bytes")
    end

    it "returns nil when the file does not exist (404)" do
      stub_request(:get, "https://api.github.com/repos/acme/widgets/contents/map.json.gz")
        .with(query: { ref: "test-impact-data" })
        .to_return(status: 404, body: JSON.generate({ "message" => "Not Found" }))

      expect(branch.read).to be_nil
    end

    it "falls back to the blobs API when content is omitted (files over 1MB)" do
      stub_request(:get, "https://api.github.com/repos/acme/widgets/contents/map.json.gz")
        .with(query: { ref: "test-impact-data" })
        .to_return(status: 200, body: JSON.generate({ "content" => "", "sha" => "blob-sha", "size" => 2_000_000 }))

      stub_request(:get, "https://api.github.com/repos/acme/widgets/git/blobs/blob-sha")
        .to_return(status: 200, body: JSON.generate({ "content" => Base64.strict_encode64("big-bytes") }))

      expect(branch.read).to eq("big-bytes")
    end

    it "keeps the path prefix of GITHUB_API_URL (GitHub Enterprise Server)" do
      original = ENV.fetch("GITHUB_API_URL", nil)
      ENV["GITHUB_API_URL"] = "https://ghe.example.com/api/v3"

      body = { "content" => Base64.strict_encode64("gzipped-bytes"), "sha" => "abc" }
      stub_request(:get, "https://ghe.example.com/api/v3/repos/acme/widgets/contents/map.json.gz")
        .with(query: { ref: "test-impact-data" })
        .to_return(status: 200, body: JSON.generate(body))

      expect(branch.read).to eq("gzipped-bytes")
    ensure
      original.nil? ? ENV.delete("GITHUB_API_URL") : ENV["GITHUB_API_URL"] = original
    end
  end

  describe "#write" do
    it "fetches the existing sha and PUTs the new content" do
      get_stub = stub_request(:get, "https://api.github.com/repos/acme/widgets/contents/map.json.gz")
                 .with(query: { ref: "test-impact-data" })
                 .to_return(status: 200, body: JSON.generate({ "content" => Base64.strict_encode64("old"), "sha" => "old-sha" }))

      put_stub = stub_request(:put, "https://api.github.com/repos/acme/widgets/contents/map.json.gz")
                 .with { |req| JSON.parse(req.body)["sha"] == "old-sha" }
                 .to_return(status: 200, body: JSON.generate({ "content" => {} }))

      branch.write("new-bytes")

      expect(get_stub).to have_been_requested
      expect(put_stub).to have_been_requested
    end

    it "omits sha when the file does not exist yet" do
      stub_request(:get, "https://api.github.com/repos/acme/widgets/contents/map.json.gz")
        .with(query: { ref: "test-impact-data" })
        .to_return(status: 404, body: JSON.generate({ "message" => "Not Found" }))

      put_stub = stub_request(:put, "https://api.github.com/repos/acme/widgets/contents/map.json.gz")
                 .with { |req| !JSON.parse(req.body).key?("sha") }
                 .to_return(status: 201, body: JSON.generate({ "content" => {} }))

      branch.write("new-bytes")

      expect(put_stub).to have_been_requested
    end

    it "retries once after refetching sha on a 409 conflict" do
      stub_request(:get, "https://api.github.com/repos/acme/widgets/contents/map.json.gz")
        .with(query: { ref: "test-impact-data" })
        .to_return(
          { status: 200, body: JSON.generate({ "content" => Base64.strict_encode64("old"), "sha" => "stale-sha" }) },
          { status: 200, body: JSON.generate({ "content" => Base64.strict_encode64("old"), "sha" => "fresh-sha" }) }
        )

      stub_request(:put, "https://api.github.com/repos/acme/widgets/contents/map.json.gz")
        .with { |req| JSON.parse(req.body)["sha"] == "stale-sha" }
        .to_return(status: 409, body: JSON.generate({ "message" => "conflict" }))

      retry_put_stub = stub_request(:put, "https://api.github.com/repos/acme/widgets/contents/map.json.gz")
                       .with { |req| JSON.parse(req.body)["sha"] == "fresh-sha" }
                       .to_return(status: 200, body: JSON.generate({ "content" => {} }))

      branch.write("new-bytes")

      expect(retry_put_stub).to have_been_requested
    end

    it "raises a DatastoreError with setup guidance when the branch does not exist" do
      stub_request(:get, "https://api.github.com/repos/acme/widgets/contents/map.json.gz")
        .with(query: { ref: "test-impact-data" })
        .to_return(status: 404, body: JSON.generate({ "message" => "No commit found for the ref test-impact-data" }))

      stub_request(:put, "https://api.github.com/repos/acme/widgets/contents/map.json.gz")
        .to_return(status: 404, body: JSON.generate({ "message" => "No commit found for the ref test-impact-data" }))

      expect { branch.write("new-bytes") }.to raise_error(TestImpact::DatastoreError, /git switch --orphan/)
    end
  end
end
