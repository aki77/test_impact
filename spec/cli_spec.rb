# frozen_string_literal: true

require "tmpdir"
require "stringio"
require "fileutils"
require "json"

RSpec.describe TestImpact::CLI do
  # generated_at defaults to now so plan's staleness check stays green.
  def write_part(dir, name, commit_sha: "abc123", generated_at: Time.now)
    map = TestImpact::Map.build(
      commit_sha: commit_sha,
      branch: "main",
      collector: { "backend" => "ddcov" },
      generated_at: generated_at,
      known_spec_files: ["spec/models/user_spec.rb"],
      index: { "app/models/user.rb" => ["spec/models/user_spec.rb"] }
    )
    TestImpact::MapSerializer.dump(map, File.join(dir, name))
  end

  describe "merge" do
    it "writes a merged map and logs a summary to stderr only, on success" do
      Dir.mktmpdir do |dir|
        input_dir = File.join(dir, "input")
        FileUtils.mkdir_p(input_dir)
        write_part(input_dir, "part-1.json.gz")
        write_part(input_dir, "part-2.json.gz")
        output_path = File.join(dir, "output", "map.json.gz")

        stdout, stderr = capture_output do
          described_class.start(["merge", "--input", input_dir, "--output", output_path])
        end

        expect(stdout).to eq("")
        expect(stderr).not_to be_empty
        expect(File).to exist(output_path)

        merged = TestImpact::MapSerializer.load(output_path)
        expect(merged.index.keys).to include("app/models/user.rb")
      end
    end

    it "warns on stderr when commit_sha differs between parts" do
      Dir.mktmpdir do |dir|
        input_dir = File.join(dir, "input")
        FileUtils.mkdir_p(input_dir)
        write_part(input_dir, "part-1.json.gz", commit_sha: "abc123")
        write_part(input_dir, "part-2.json.gz", commit_sha: "def456")
        output_path = File.join(dir, "output", "map.json.gz")

        _, stderr = capture_output do
          described_class.start(["merge", "--input", input_dir, "--output", output_path])
        end

        expect(stderr).to include("commit_sha mismatch")
      end
    end

    it "exits with status 1 and writes an error to stderr when no parts are found" do
      Dir.mktmpdir do |dir|
        input_dir = File.join(dir, "empty_input")
        FileUtils.mkdir_p(input_dir)

        stdout, stderr = capture_output do
          expect do
            described_class.start(["merge", "--input", input_dir])
          end.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
        end

        expect(stdout).to eq("")
        expect(stderr).to include("error")
      end
    end
  end

  describe "info" do
    it "prints map statistics to stdout" do
      Dir.mktmpdir do |dir|
        map_path = File.join(dir, "map.json.gz")
        map = TestImpact::Map.build(
          commit_sha: "abc123",
          branch: "main",
          collector: { "backend" => "ddcov" },
          generated_at: Time.utc(2026, 8, 8),
          known_spec_files: ["spec/models/user_spec.rb"],
          index: { "app/models/user.rb" => ["spec/models/user_spec.rb"] }
        )
        TestImpact::MapSerializer.dump(map, map_path)

        stdout, = capture_output do
          described_class.start(["info", "--map", map_path])
        end

        expect(stdout).to include("schema_version: 1")
        expect(stdout).to include("commit_sha: abc123")
        expect(stdout).to include("branch: main")
        expect(stdout).to include("backend: ddcov")
        expect(stdout).to include("source_files: 1")
        expect(stdout).to include("spec_files: 1")
        expect(stdout).to include("known_spec_files: 1")
      end
    end

    it "exits with status 1 and writes an error to stderr when the map file is missing" do
      Dir.mktmpdir do |dir|
        map_path = File.join(dir, "missing.json.gz")

        expect do
          capture_output { described_class.start(["info", "--map", map_path]) }
        end.to raise_error(SystemExit) { |e| expect(e.status).to eq(1) }
      end
    end
  end

  describe "plan" do
    def run_plan(dir, map_path, base: "base-point", extra_args: [])
      allow(TestImpact::Paths).to receive(:repo_root).and_return(dir)

      status = nil
      stdout, stderr = capture_output do
        begin
          described_class.start(["plan", "--map", map_path, "--base", base, *extra_args])
        rescue SystemExit => e
          status = e.status
        end
      end
      [stdout, stderr, status]
    end

    it "falls back to all with the default exit code when the map file is missing" do
      GitSandbox.create do |dir|
        GitSandbox.write(dir, "a.rb", "1")
        GitSandbox.commit(dir, "init")
        GitSandbox.run(dir, "tag", "base-point")

        stdout, stderr, status = run_plan(dir, File.join(dir, "missing.json.gz"))

        expect(stdout).to eq("")
        expect(stderr).to include("mode: all")
        expect(status).to eq(10)
      end
    end

    it "falls back to all when the map file is corrupted" do
      GitSandbox.create do |dir|
        GitSandbox.write(dir, "a.rb", "1")
        GitSandbox.commit(dir, "init")
        GitSandbox.run(dir, "tag", "base-point")
        map_path = File.join(dir, "corrupt.json.gz")
        File.binwrite(map_path, "not a gzip stream")

        stdout, stderr, status = run_plan(dir, map_path)

        expect(stdout).to eq("")
        expect(stderr).to include("could not read map")
        expect(stderr).to include("mode: all")
        expect(status).to eq(10)
      end
    end

    it "prints the impacted spec files on stdout in lines format and exits 0" do
      GitSandbox.create do |dir|
        GitSandbox.write(dir, "lib/user.rb", "1")
        GitSandbox.write(dir, "spec/user_spec.rb", "1")
        base_sha = GitSandbox.commit(dir, "init")
        GitSandbox.run(dir, "tag", "base-point")

        Dir.mktmpdir do |map_dir|
          map = TestImpact::Map.build(
            commit_sha: base_sha,
            branch: "main",
            collector: { "backend" => "ddcov" },
            known_spec_files: ["spec/user_spec.rb"],
            index: { "lib/user.rb" => ["spec/user_spec.rb"] }
          )
          map_path = File.join(map_dir, "map.json.gz")
          TestImpact::MapSerializer.dump(map, map_path)

          GitSandbox.write(dir, "lib/user.rb", "2")
          GitSandbox.commit(dir, "modify user")

          stdout, stderr, status = run_plan(dir, map_path)

          expect(stdout).to eq("spec/user_spec.rb\n")
          expect(stderr).to include("mode: partial")
          expect(status).to eq(0)
        end
      end
    end

    it "prints an empty stdout in lines format when there is nothing to run" do
      GitSandbox.create do |dir|
        GitSandbox.write(dir, "lib/user.rb", "1")
        base_sha = GitSandbox.commit(dir, "init")
        GitSandbox.run(dir, "tag", "base-point")

        Dir.mktmpdir do |map_dir|
          map = TestImpact::Map.build(
            commit_sha: base_sha,
            branch: "main",
            collector: { "backend" => "ddcov" },
            known_spec_files: [],
            index: { "lib/user.rb" => [] }
          )
          map_path = File.join(map_dir, "map.json.gz")
          TestImpact::MapSerializer.dump(map, map_path)

          stdout, stderr, status = run_plan(dir, map_path)

          expect(stdout).to eq("")
          expect(stderr).to include("mode: none")
          expect(status).to eq(0)
        end
      end
    end

    it "always exits 0 in json format, even when mode is all" do
      GitSandbox.create do |dir|
        GitSandbox.write(dir, "a.rb", "1")
        GitSandbox.commit(dir, "init")
        GitSandbox.run(dir, "tag", "base-point")

        stdout, stderr, status = run_plan(dir, File.join(dir, "missing.json.gz"), extra_args: ["--format", "json"])

        expect(status).to eq(0)
        payload = JSON.parse(stdout)
        expect(payload["mode"]).to eq("all")
        expect(payload["spec_files"]).to eq([])
        expect(stderr).to include("mode: all")
      end
    end

    it "honors --fallback-to-all-exit-code for the all case in lines format" do
      GitSandbox.create do |dir|
        GitSandbox.write(dir, "a.rb", "1")
        GitSandbox.commit(dir, "init")
        GitSandbox.run(dir, "tag", "base-point")

        stdout, _stderr, status = run_plan(
          dir, File.join(dir, "missing.json.gz"), extra_args: ["--fallback-to-all-exit-code", "42"]
        )

        expect(stdout).to eq("")
        expect(status).to eq(42)
      end
    end
  end
end
