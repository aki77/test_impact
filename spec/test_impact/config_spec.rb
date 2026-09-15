# frozen_string_literal: true

require 'tmpdir'
require 'fileutils'

RSpec.describe TestImpact::Config do
  let(:tmp_dir) { Dir.mktmpdir }

  after { FileUtils.remove_entry(tmp_dir) }

  def write_yaml(content)
    path = File.join(tmp_dir, '.test_impact.yml')
    File.write(path, content)
    path
  end

  context 'when the config file does not exist' do
    it 'falls back to all default values' do
      path = File.join(tmp_dir, 'nonexistent.yml')

      config = described_class.load(path)

      expect(config.base).to eq('origin/main')
      expect(config.max_age_days).to eq(7)
      expect(config.always_run).to eq([])
      expect(config.global_files).to eq(TestImpact::Config::DEFAULT_GLOBAL_FILES)
      expect(config.collector).to eq({ 'allocation_tracing' => true, 'ignored_paths' => ['vendor/', 'tmp/'] })
    end
  end

  context 'when the config file exists' do
    it 'overrides only the specified keys' do
      path = write_yaml(<<~YAML)
        base: origin/develop
        max_age_days: 3
        always_run:
          - spec/smoke_spec.rb
      YAML

      config = described_class.load(path)

      expect(config.base).to eq('origin/develop')
      expect(config.max_age_days).to eq(3)
      expect(config.always_run).to eq(['spec/smoke_spec.rb'])
      expect(config.global_files).to eq(TestImpact::Config::DEFAULT_GLOBAL_FILES)
    end

    it 'replaces global_files entirely rather than merging' do
      path = write_yaml(<<~YAML)
        global_files:
          - custom_file.txt
      YAML

      config = described_class.load(path)

      expect(config.global_files).to eq(['custom_file.txt'])
    end

    it 'shallow-merges collector with the defaults' do
      path = write_yaml(<<~YAML)
        collector:
          allocation_tracing: false
      YAML

      config = described_class.load(path)

      expect(config.collector).to eq({ 'allocation_tracing' => false, 'ignored_paths' => ['vendor/', 'tmp/'] })
    end

    it 'falls back to defaults when keys are present but nil' do
      path = write_yaml(<<~YAML)
        base:
        always_run:
        collector:
      YAML

      config = described_class.load(path)

      expect(config.base).to eq('origin/main')
      expect(config.always_run).to eq([])
      expect(config.collector).to eq(TestImpact::Config::DEFAULT_COLLECTOR)
    end

    it 'falls back to the default when a collector key is present but nil' do
      path = write_yaml(<<~YAML)
        collector:
          ignored_paths:
      YAML

      config = described_class.load(path)

      expect(config.collector).to eq({ 'allocation_tracing' => true, 'ignored_paths' => ['vendor/', 'tmp/'] })
    end

    it 'falls back to the default when allocation_tracing is present but nil' do
      path = write_yaml(<<~YAML)
        collector:
          allocation_tracing:
      YAML

      config = described_class.load(path)

      expect(config.collector['allocation_tracing']).to be(true)
    end

    it 'keeps allocation_tracing false because false is not nil' do
      path = write_yaml(<<~YAML)
        collector:
          allocation_tracing: false
      YAML

      config = described_class.load(path)

      expect(config.collector['allocation_tracing']).to be(false)
    end

    it 'defaults ignore to an empty list when unspecified' do
      path = write_yaml(<<~YAML)
        base: origin/develop
      YAML

      config = described_class.load(path)

      expect(config.ignore).to eq([])
    end

    it 'defaults ignore to an empty list when present but nil' do
      path = write_yaml(<<~YAML)
        ignore:
      YAML

      config = described_class.load(path)

      expect(config.ignore).to eq([])
    end

    it 'uses the configured ignore patterns' do
      path = write_yaml(<<~YAML)
        ignore:
          - a
      YAML

      config = described_class.load(path)

      expect(config.ignore).to eq(['a'])
    end
  end
end
