# frozen_string_literal: true

require "tmpdir"
require "fileutils"

RSpec.describe TestImpact::Config do
  around do |example|
    Dir.mktmpdir do |dir|
      @tmp_dir = dir
      example.run
    end
  end

  def write_yaml(content)
    path = File.join(@tmp_dir, ".test_impact.yml")
    File.write(path, content)
    path
  end

  context "when the config file does not exist" do
    it "falls back to all default values" do
      path = File.join(@tmp_dir, "nonexistent.yml")

      config = described_class.load(path)

      expect(config.base).to eq("origin/main")
      expect(config.max_age_days).to eq(7)
      expect(config.always_run).to eq([])
      expect(config.global_files).to eq(TestImpact::Config::DEFAULT_GLOBAL_FILES)
      expect(config.view_fallback).to eq("all")
      expect(config.collector).to eq({ "allocation_tracing" => true, "ignored_paths" => ["vendor/", "tmp/"] })
    end
  end

  context "when the config file exists" do
    it "overrides only the specified keys" do
      path = write_yaml(<<~YAML)
        base: origin/develop
        max_age_days: 3
        always_run:
          - spec/smoke_spec.rb
      YAML

      config = described_class.load(path)

      expect(config.base).to eq("origin/develop")
      expect(config.max_age_days).to eq(3)
      expect(config.always_run).to eq(["spec/smoke_spec.rb"])
      expect(config.global_files).to eq(TestImpact::Config::DEFAULT_GLOBAL_FILES)
      expect(config.view_fallback).to eq("all")
    end

    it "replaces global_files entirely rather than merging" do
      path = write_yaml(<<~YAML)
        global_files:
          - custom_file.txt
      YAML

      config = described_class.load(path)

      expect(config.global_files).to eq(["custom_file.txt"])
    end

    it "shallow-merges collector with the defaults" do
      path = write_yaml(<<~YAML)
        collector:
          allocation_tracing: false
      YAML

      config = described_class.load(path)

      expect(config.collector).to eq({ "allocation_tracing" => false, "ignored_paths" => ["vendor/", "tmp/"] })
    end

    it "falls back to defaults when keys are present but nil" do
      path = write_yaml(<<~YAML)
        base:
        always_run:
        collector:
      YAML

      config = described_class.load(path)

      expect(config.base).to eq("origin/main")
      expect(config.always_run).to eq([])
      expect(config.collector).to eq(TestImpact::Config::DEFAULT_COLLECTOR)
    end
  end
end
