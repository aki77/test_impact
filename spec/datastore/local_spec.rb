# frozen_string_literal: true

require "tmpdir"

RSpec.describe TestImpact::Datastore::Local do
  describe "#read" do
    it "returns nil when the file does not exist" do
      Dir.mktmpdir do |dir|
        local = described_class.new(File.join(dir, "map.json.gz"))

        expect(local.read).to be_nil
      end
    end

    it "round-trips bytes written via #write" do
      Dir.mktmpdir do |dir|
        local = described_class.new(File.join(dir, "map.json.gz"))

        local.write("gzipped-bytes")

        expect(local.read).to eq("gzipped-bytes")
      end
    end

    it "creates intermediate directories on write" do
      Dir.mktmpdir do |dir|
        path = File.join(dir, "nested", "sub", "map.json.gz")
        local = described_class.new(path)

        local.write("bytes")

        expect(File).to exist(path)
      end
    end

    it "defaults to map.json.gz when given a directory path" do
      Dir.mktmpdir do |dir|
        local = described_class.new(dir)

        local.write("bytes")

        expect(File.binread(File.join(dir, "map.json.gz"))).to eq("bytes")
        expect(local.read).to eq("bytes")
      end
    end
  end
end
