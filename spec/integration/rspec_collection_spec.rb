# frozen_string_literal: true

require "open3"
require "tmpdir"
require "fileutils"

RSpec.describe "RSpec coverage collection", :ddcov do
  GEM_ROOT = File.expand_path("../..", __dir__)
  FIXTURE_ROOT = File.join(GEM_ROOT, "spec", "fixtures", "sample_app")

  RUN = lambda do |*cmd, chdir|
    _, stderr, status = Open3.capture3(*cmd, chdir: chdir)
    raise "command failed: #{cmd.join(" ")}\n#{stderr}" unless status.success?
  end

  let(:map) { @map }

  before(:context) do
    Dir.mktmpdir("test_impact_integration") do |tmpdir|
      app_dir = File.join(tmpdir, "sample_app")
      part_dir = File.join(tmpdir, "parts")
      FileUtils.mkdir_p(app_dir)
      FileUtils.cp_r(File.join(FIXTURE_ROOT, "."), app_dir)

      # Give the fixture its own git repository so Paths.repo_root resolves to
      # the sample app rather than the gem repository that contains it.
      RUN.call("git", "init", "--quiet", "--initial-branch", "main", ".", app_dir)
      RUN.call("git", "add", "-A", app_dir)
      RUN.call("git", "-c", "user.name=test", "-c", "user.email=test@example.com",
               "commit", "--quiet", "-m", "init", app_dir)

      env = {
        "BUNDLE_GEMFILE" => File.join(GEM_ROOT, "Gemfile"),
        "RUBYOPT" => "-I#{File.join(GEM_ROOT, "lib")}",
        "TEST_IMPACT_COLLECT" => "1",
        "TEST_IMPACT_REQUIRE_COVERAGE" => "1",
        "TEST_IMPACT_PART_DIR" => part_dir
      }

      stdout, stderr, status = Open3.capture3(env, "bundle", "exec", "rspec", chdir: app_dir)
      unless status.success?
        raise "sample app rspec failed (#{status.exitstatus})\n" \
              "--- stdout ---\n#{stdout}\n--- stderr ---\n#{stderr}"
      end

      parts = Dir.glob(File.join(part_dir, "part-*.json.gz"))
      unless parts.size == 1
        raise "expected exactly one part file, got #{parts.size}\n" \
              "--- stdout ---\n#{stdout}\n--- stderr ---\n#{stderr}"
      end

      @map = TestImpact::MapSerializer.load(parts.first)
    end
  end

  it "uses the ddcov backend" do
    expect(map.collector["backend"]).to eq("ddcov")
    expect(map.valid_backend?).to be(true)
  end

  it "records git metadata from the sample app repository" do
    expect(map.commit_sha).to match(/\A[0-9a-f]{40}\z/)
    expect(map.branch).to eq("main")
  end

  it "attributes calculator.rb to calculator_spec.rb only" do
    expect(map.specs_for("lib/calculator.rb")).to eq(Set["spec/calculator_spec.rb"])
  end

  it "attributes greeter.rb to greeter_spec.rb only" do
    expect(map.specs_for("lib/greeter.rb")).to eq(Set["spec/greeter_spec.rb"])
  end

  it "records the known spec files" do
    expect(map.known_spec_files).to eq(Set["spec/calculator_spec.rb", "spec/greeter_spec.rb"])
  end

  it "does not index spec files as sources" do
    expect(map.index.keys).to all(start_with("lib/"))
  end
end
