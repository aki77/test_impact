# frozen_string_literal: true

require "tmpdir"
require "test_impact/recorder"
require "test_impact/collector/null_backend"

RSpec.describe TestImpact::Recorder do
  subject(:recorder) { described_class.new(backend: backend, config: config) }

  let(:backend) { instance_double(TestImpact::Collector::NullBackend, name: "ddcov") }
  let(:config) { TestImpact::Config.new }
  let(:repo_root) { "/repo" }

  before { allow(TestImpact::Paths).to receive(:repo_root).and_return(repo_root) }

  def abs(rel)
    File.join(repo_root, rel)
  end

  describe "#start_example" do
    it "starts the backend" do
      allow(backend).to receive(:start)
      recorder.start_example
      expect(backend).to have_received(:start)
    end
  end

  describe "#finish_example" do
    def finish(covered, spec_rel: "spec/foo_spec.rb")
      allow(backend).to receive(:stop).and_return(covered)
      recorder.finish_example(abs(spec_rel))
    end

    it "indexes covered source files by spec" do
      finish({ abs("lib/a.rb") => true, abs("app/models/b.rb") => true })

      expect(recorder.index).to eq(
        "lib/a.rb" => Set["spec/foo_spec.rb"],
        "app/models/b.rb" => Set["spec/foo_spec.rb"]
      )
    end

    it "accumulates multiple specs for the same source file" do
      finish({ abs("lib/a.rb") => true }, spec_rel: "spec/foo_spec.rb")
      finish({ abs("lib/a.rb") => true }, spec_rel: "spec/bar_spec.rb")

      expect(recorder.index["lib/a.rb"]).to eq(Set["spec/foo_spec.rb", "spec/bar_spec.rb"])
    end

    it "excludes files outside the repository" do
      finish({ "/elsewhere/gems/rspec.rb" => true, abs("lib/a.rb") => true })

      expect(recorder.index.keys).to contain_exactly("lib/a.rb")
    end

    it "excludes configured ignored_paths prefixes" do
      finish({ abs("vendor/bundle/x.rb") => true, abs("tmp/cache.rb") => true, abs("lib/a.rb") => true })

      expect(recorder.index.keys).to contain_exactly("lib/a.rb")
    end

    it "excludes the spec file itself and other spec files" do
      finish({ abs("spec/foo_spec.rb") => true, abs("spec/support/helper.rb") => true, abs("lib/a.rb") => true })

      expect(recorder.index.keys).to contain_exactly("lib/a.rb")
    end

    it "ignores an example whose spec path is outside the repository" do
      allow(backend).to receive(:stop).and_return({ abs("lib/a.rb") => true })
      recorder.finish_example("/elsewhere/spec/foo_spec.rb")

      expect(recorder.index).to be_empty
    end

    it "handles a nil coverage result" do
      expect { finish(nil) }.not_to raise_error
      expect(recorder.index).to be_empty
    end

    it "indexes a view template path like any other source file" do
      finish({ abs("app/views/users/show.html.erb") => true })

      expect(recorder.index).to eq(
        "app/views/users/show.html.erb" => Set["spec/foo_spec.rb"]
      )
    end
  end

  describe "#record_known_spec_files" do
    it "relativizes and stores spec paths" do
      recorder.record_known_spec_files([abs("spec/foo_spec.rb"), abs("spec/bar_spec.rb")])

      expect(recorder.known_spec_files).to eq(Set["spec/foo_spec.rb", "spec/bar_spec.rb"])
    end

    it "excludes paths outside the repository" do
      recorder.record_known_spec_files([abs("spec/foo_spec.rb"), "/elsewhere/spec/x_spec.rb"])

      expect(recorder.known_spec_files).to eq(Set["spec/foo_spec.rb"])
    end
  end

  describe "#write_part" do
    around do |example|
      Dir.mktmpdir do |dir|
        @dir = dir
        example.run
      end
    end

    before do
      allow(backend).to receive(:stop).and_return({ abs("lib/a.rb") => true })
      recorder.finish_example(abs("spec/foo_spec.rb"))
      recorder.record_known_spec_files([abs("spec/foo_spec.rb")])
    end

    it "writes a loadable part file" do
      path = recorder.write_part(@dir)

      expect(File.basename(path)).to match(/\Apart-\d+-.+-[0-9a-f]{8}\.json\.gz\z/)

      map = TestImpact::MapSerializer.load(path)
      expect(map.index).to eq("lib/a.rb" => Set["spec/foo_spec.rb"])
      expect(map.known_spec_files).to eq(Set["spec/foo_spec.rb"])
      expect(map.collector).to eq("backend" => "ddcov", "allocation_tracing" => true)
    end

    it "falls back to empty git metadata when the repo root is unusable" do
      map = TestImpact::MapSerializer.load(recorder.write_part(@dir))

      expect(map.commit_sha).to eq("")
      expect(map.branch).to eq("")
    end

    it "records git metadata from a real repository" do
      GitSandbox.create do |git_root|
        GitSandbox.write(git_root, "README.md", "x")
        GitSandbox.commit(git_root, "init")

        allow(TestImpact::Paths).to receive(:repo_root).and_return(git_root)
        map = TestImpact::MapSerializer.load(recorder.write_part(@dir))

        expect(map.commit_sha).to match(/\A[0-9a-f]{40}\z/)
        expect(map.branch).to eq("main")
      end
    end

    it "creates the target directory when missing" do
      nested = File.join(@dir, "a", "b")
      recorder.write_part(nested)

      expect(Dir.glob(File.join(nested, "part-*.json.gz")).size).to eq(1)
    end

    it "is a no-op on a second call" do
      recorder.write_part(@dir)
      expect(recorder.write_part(@dir)).to be_nil

      expect(Dir.glob(File.join(@dir, "part-*.json.gz")).size).to eq(1)
    end

    it "uses TEST_IMPACT_PART_DIR by default" do
      original = ENV.fetch("TEST_IMPACT_PART_DIR", nil)
      ENV["TEST_IMPACT_PART_DIR"] = @dir
      recorder.write_part
      expect(Dir.glob(File.join(@dir, "part-*.json.gz")).size).to eq(1)
    ensure
      original.nil? ? ENV.delete("TEST_IMPACT_PART_DIR") : ENV["TEST_IMPACT_PART_DIR"] = original
    end

    it "records the null backend name when coverage is unavailable" do
      null_recorder = described_class.new(backend: TestImpact::Collector::NullBackend.new, config: config)
      map = TestImpact::MapSerializer.load(null_recorder.write_part(@dir))

      expect(map.collector["backend"]).to eq("null")
      expect(map.valid_backend?).to be(false)
    end
  end
end
