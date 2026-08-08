# frozen_string_literal: true

require "webmock/rspec"
require "zip"
require "stringio"
require "tmpdir"
require "fileutils"

RSpec.describe TestImpact::Datastore::Artifact do
  around do |example|
    Dir.mktmpdir do |dir|
      Dir.chdir(dir) { example.run }
    end
  end

  def build_zip(entries)
    io = StringIO.new
    Zip::OutputStream.write_buffer(io) do |zos|
      entries.each do |name, content|
        zos.put_next_entry(name)
        zos.write(content)
      end
    end
    io.rewind
    io.read
  end

  let(:artifact) { described_class.new(owner: "acme", repo: "widgets", client: TestImpact::Datastore::GithubClient.new(token: "tok")) }

  describe "#read" do
    it "returns nil when there are no artifacts" do
      stub_request(:get, "https://api.github.com/repos/acme/widgets/actions/artifacts")
        .with(query: { name: "test-impact-map", per_page: "100" })
        .to_return(status: 200, body: JSON.generate({ "artifacts" => [] }))

      expect(artifact.read).to be_nil
    end

    it "selects the latest non-expired artifact and extracts map.json.gz from its zip" do
      artifacts = [
        { "id" => 1, "expired" => false, "created_at" => "2026-08-01T00:00:00Z" },
        { "id" => 2, "expired" => true, "created_at" => "2026-08-05T00:00:00Z" },
        { "id" => 3, "expired" => false, "created_at" => "2026-08-03T00:00:00Z" }
      ]
      stub_request(:get, "https://api.github.com/repos/acme/widgets/actions/artifacts")
        .with(query: { name: "test-impact-map", per_page: "100" })
        .to_return(status: 200, body: JSON.generate({ "artifacts" => artifacts }))

      stub_request(:get, "https://api.github.com/repos/acme/widgets/actions/artifacts/3/zip")
        .to_return(status: 302, headers: { "Location" => "https://productionresultssa.blob.core.windows.net/artifact3" })

      zip_bytes = build_zip("map.json.gz" => "gzipped-map-bytes")
      stub_request(:get, "https://productionresultssa.blob.core.windows.net/artifact3")
        .to_return(status: 200, body: zip_bytes)

      expect(artifact.read).to eq("gzipped-map-bytes")
    end

    it "falls back to the first .json.gz entry when map.json.gz is absent" do
      stub_request(:get, "https://api.github.com/repos/acme/widgets/actions/artifacts")
        .with(query: { name: "test-impact-map", per_page: "100" })
        .to_return(status: 200, body: JSON.generate({ "artifacts" => [{ "id" => 9, "expired" => false, "created_at" => "2026-08-01T00:00:00Z" }] }))

      stub_request(:get, "https://api.github.com/repos/acme/widgets/actions/artifacts/9/zip")
        .to_return(status: 302, headers: { "Location" => "https://example.test/artifact9" })

      zip_bytes = build_zip("other.json.gz" => "fallback-bytes")
      stub_request(:get, "https://example.test/artifact9")
        .to_return(status: 200, body: zip_bytes)

      expect(artifact.read).to eq("fallback-bytes")
    end

    it "raises DatastoreError when the downloaded bytes are not a valid zip" do
      stub_request(:get, "https://api.github.com/repos/acme/widgets/actions/artifacts")
        .with(query: { name: "test-impact-map", per_page: "100" })
        .to_return(status: 200, body: JSON.generate({ "artifacts" => [{ "id" => 9, "expired" => false, "created_at" => "2026-08-01T00:00:00Z" }] }))

      stub_request(:get, "https://api.github.com/repos/acme/widgets/actions/artifacts/9/zip")
        .to_return(status: 302, headers: { "Location" => "https://example.test/artifact9" })

      stub_request(:get, "https://example.test/artifact9")
        .to_return(status: 200, body: "<html>error page</html>")

      expect { artifact.read }.to raise_error(TestImpact::DatastoreError, /not a valid zip/)
    end

    it "raises when the artifact zip contains no map entry" do
      stub_request(:get, "https://api.github.com/repos/acme/widgets/actions/artifacts")
        .with(query: { name: "test-impact-map", per_page: "100" })
        .to_return(status: 200, body: JSON.generate({ "artifacts" => [{ "id" => 9, "expired" => false, "created_at" => "2026-08-01T00:00:00Z" }] }))

      stub_request(:get, "https://api.github.com/repos/acme/widgets/actions/artifacts/9/zip")
        .to_return(status: 302, headers: { "Location" => "https://example.test/artifact9" })

      stub_request(:get, "https://example.test/artifact9")
        .to_return(status: 200, body: build_zip("something-else.txt" => "not a map"))

      expect { artifact.read }.to raise_error(TestImpact::DatastoreError, /did not contain/)
    end

    it "raises when the zip endpoint fails instead of returning nil" do
      stub_request(:get, "https://api.github.com/repos/acme/widgets/actions/artifacts")
        .with(query: { name: "test-impact-map", per_page: "100" })
        .to_return(status: 200, body: JSON.generate({ "artifacts" => [{ "id" => 9, "expired" => false, "created_at" => "2026-08-01T00:00:00Z" }] }))

      stub_request(:get, "https://api.github.com/repos/acme/widgets/actions/artifacts/9/zip")
        .to_return(status: 403, body: JSON.generate({ "message" => "Forbidden" }))

      expect { artifact.read }.to raise_error(TestImpact::DatastoreError, /403/)
    end
  end

  describe "#write" do
    it "writes to the fallback path and prints upload guidance to stderr" do
      _, stderr = capture_output { artifact.write("gzipped-bytes") }

      expect(File.binread(".test_impact/map.json.gz")).to eq("gzipped-bytes")
      expect(stderr).to include("actions/upload-artifact")
      expect(stderr).to include("test-impact-map")
    end

    it "does not require a GitHub token (client is built lazily for read only)" do
      expect(TestImpact::Datastore::GithubClient).not_to receive(:new)

      tokenless = described_class.new(owner: "acme", repo: "widgets")
      capture_output { tokenless.write("gzipped-bytes") }

      expect(File.binread(".test_impact/map.json.gz")).to eq("gzipped-bytes")
    end
  end
end
