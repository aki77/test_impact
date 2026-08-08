# frozen_string_literal: true

RSpec.describe TestImpact::Datastore::Registry do
  around do |example|
    original = ENV["GITHUB_TOKEN"]
    ENV["GITHUB_TOKEN"] = "test-token"
    example.run
  ensure
    ENV["GITHUB_TOKEN"] = original
  end

  describe ".build" do
    context "with local:// urls" do
      it "resolves to a Local datastore rooted at the given path" do
        datastore = described_class.build("local:///tmp/foo/map.json.gz")

        expect(datastore).to be_a(TestImpact::Datastore::Local)
        expect(datastore.instance_variable_get(:@path)).to eq("/tmp/foo/map.json.gz")
      end

      it "defaults to map.json.gz when the path has no file component" do
        datastore = described_class.build("local:///tmp/foo")

        expect(datastore.instance_variable_get(:@path)).to eq("/tmp/foo/map.json.gz")
      end
    end

    context "with file:// urls" do
      it "resolves to a Local datastore" do
        datastore = described_class.build("file:///tmp/bar/map.json.gz")

        expect(datastore).to be_a(TestImpact::Datastore::Local)
        expect(datastore.instance_variable_get(:@path)).to eq("/tmp/bar/map.json.gz")
      end
    end

    context "with artifact:// urls" do
      it "parses owner/repo and uses the default artifact name" do
        datastore = described_class.build("artifact://acme/widgets")

        expect(datastore).to be_a(TestImpact::Datastore::Artifact)
        expect(datastore.instance_variable_get(:@owner)).to eq("acme")
        expect(datastore.instance_variable_get(:@repo)).to eq("widgets")
        expect(datastore.instance_variable_get(:@name)).to eq("test-impact-map")
      end

      it "parses an explicit artifact name" do
        datastore = described_class.build("artifact://acme/widgets/custom-name")

        expect(datastore.instance_variable_get(:@name)).to eq("custom-name")
      end
    end

    context "with branch:// urls" do
      it "uses default branch and path when omitted" do
        datastore = described_class.build("branch://acme/widgets")

        expect(datastore).to be_a(TestImpact::Datastore::Branch)
        expect(datastore.instance_variable_get(:@owner)).to eq("acme")
        expect(datastore.instance_variable_get(:@repo)).to eq("widgets")
        expect(datastore.instance_variable_get(:@branch)).to eq("test-impact-data")
        expect(datastore.instance_variable_get(:@path)).to eq("map.json.gz")
      end

      it "parses an explicit branch with @branch syntax" do
        datastore = described_class.build("branch://acme/widgets@custom-branch")

        expect(datastore.instance_variable_get(:@branch)).to eq("custom-branch")
      end

      it "parses an explicit path" do
        datastore = described_class.build("branch://acme/widgets/data/map.json.gz")

        expect(datastore.instance_variable_get(:@path)).to eq("data/map.json.gz")
      end

      it "falls back to the default path for a trailing slash" do
        datastore = described_class.build("branch://acme/widgets/")

        expect(datastore.instance_variable_get(:@path)).to eq("map.json.gz")
      end

      it "falls back to the default branch for a trailing @" do
        datastore = described_class.build("branch://acme/widgets@")

        expect(datastore.instance_variable_get(:@branch)).to eq("test-impact-data")
      end

      it "parses a branch name containing slashes" do
        datastore = described_class.build("branch://acme/widgets@release/1.0")

        expect(datastore.instance_variable_get(:@branch)).to eq("release/1.0")
        expect(datastore.instance_variable_get(:@path)).to eq("map.json.gz")
      end

      it "parses a path combined with a slash-containing branch" do
        datastore = described_class.build("branch://acme/widgets/data/map.json.gz@feature/x")

        expect(datastore.instance_variable_get(:@path)).to eq("data/map.json.gz")
        expect(datastore.instance_variable_get(:@branch)).to eq("feature/x")
      end

      it "raises DatastoreError for a string that is not a valid URI" do
        expect do
          described_class.build("branch://acme/wid gets")
        end.to raise_error(TestImpact::DatastoreError, /invalid datastore url/)
      end

      it "parses both a path and @branch (branch comes last)" do
        datastore = described_class.build("branch://acme/widgets/data/map.json.gz@custom-branch")

        expect(datastore.instance_variable_get(:@branch)).to eq("custom-branch")
        expect(datastore.instance_variable_get(:@path)).to eq("data/map.json.gz")
      end
    end

    context "with github:// urls" do
      it "resolves the same as branch://" do
        datastore = described_class.build("github://acme/widgets@custom-branch")

        expect(datastore).to be_a(TestImpact::Datastore::Branch)
        expect(datastore.instance_variable_get(:@branch)).to eq("custom-branch")
      end
    end

    context "with an unknown scheme" do
      it "raises a DatastoreError" do
        expect { described_class.build("s3://bucket/key") }.to raise_error(TestImpact::DatastoreError, /unknown datastore scheme/)
      end
    end
  end
end
