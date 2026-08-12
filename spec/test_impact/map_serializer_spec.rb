# frozen_string_literal: true

require 'tmpdir'
require 'zlib'
require 'json'
require 'stringio'

RSpec.describe TestImpact::MapSerializer do
  let(:map) do
    TestImpact::Map.build(
      commit_sha: 'abc123',
      branch: 'main',
      collector: { 'backend' => 'ddcov' },
      generated_at: Time.utc(2026, 8, 8, 0, 0, 0),
      known_spec_files: ['spec/models/user_spec.rb', 'spec/models/account_spec.rb'],
      index: { 'app/models/user.rb' => ['spec/models/user_spec.rb'] }
    )
  end

  describe '.dump and .load via file path' do
    it 'round-trips a map through disk' do
      Dir.mktmpdir do |dir|
        path = File.join(dir, 'map.json.gz')

        described_class.dump(map, path)
        loaded = described_class.load(path)

        expect(loaded).to eq(map)
      end
    end
  end

  describe '.dump_bytes and .load_bytes' do
    it 'round-trips a map through an in-memory byte string' do
      bytes = described_class.dump_bytes(map)

      expect(bytes.encoding).to eq(Encoding::ASCII_8BIT)

      loaded = described_class.load_bytes(bytes)

      expect(loaded).to eq(map)
    end

    it 'serializes known_spec_files and index values as sorted arrays' do
      bytes = described_class.dump_bytes(map)
      json = Zlib::GzipReader.new(StringIO.new(bytes)).read
      data = JSON.parse(json)

      expect(data['known_spec_files']).to eq(['spec/models/account_spec.rb', 'spec/models/user_spec.rb'])
      expect(data['index']['app/models/user.rb']).to eq(['spec/models/user_spec.rb'])
    end
  end

  describe '.load with an unsupported schema_version' do
    it 'raises TestImpact::SchemaVersionError' do
      payload = {
        'schema_version' => 2,
        'generated_at' => '2026-08-08T00:00:00Z',
        'commit_sha' => 'abc123',
        'branch' => 'main',
        'collector' => {},
        'known_spec_files' => [],
        'index' => {},
      }

      io = StringIO.new
      io.set_encoding(Encoding::BINARY)
      gz = Zlib::GzipWriter.new(io)
      gz.write(JSON.generate(payload))
      gz.close

      expect { described_class.load_bytes(io.string) }.to raise_error(TestImpact::SchemaVersionError)
    end

    it 'raises MapFormatError when collector is null' do
      payload = {
        'schema_version' => TestImpact::Map::SCHEMA_VERSION,
        'generated_at' => '2026-08-08T00:00:00Z',
        'commit_sha' => 'abc',
        'branch' => 'main',
        'collector' => nil,
        'known_spec_files' => [],
        'index' => {},
      }

      io = StringIO.new
      io.set_encoding(Encoding::BINARY)
      gz = Zlib::GzipWriter.new(io)
      gz.write(JSON.generate(payload))
      gz.close

      expect { described_class.load_bytes(io.string) }.to raise_error(TestImpact::MapFormatError)
    end

    it 'raises MapFormatError when an index value is null' do
      payload = {
        'schema_version' => TestImpact::Map::SCHEMA_VERSION,
        'generated_at' => '2026-08-08T00:00:00Z',
        'commit_sha' => 'abc',
        'branch' => 'main',
        'collector' => { 'backend' => 'ddcov' },
        'known_spec_files' => [],
        'index' => { 'app/models/user.rb' => nil },
      }

      io = StringIO.new
      io.set_encoding(Encoding::BINARY)
      gz = Zlib::GzipWriter.new(io)
      gz.write(JSON.generate(payload))
      gz.close

      expect { described_class.load_bytes(io.string) }.to raise_error(TestImpact::MapFormatError)
    end

    it 'raises MapFormatError when required fields are missing or malformed' do
      payload = { 'schema_version' => TestImpact::Map::SCHEMA_VERSION, 'generated_at' => nil, 'index' => nil }

      io = StringIO.new
      io.set_encoding(Encoding::BINARY)
      gz = Zlib::GzipWriter.new(io)
      gz.write(JSON.generate(payload))
      gz.close

      expect { described_class.load_bytes(io.string) }.to raise_error(TestImpact::MapFormatError)
    end
  end
end
