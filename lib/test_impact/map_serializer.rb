# frozen_string_literal: true

require 'json'
require 'zlib'
require 'stringio'
require 'time'

module TestImpact
  module MapSerializer
    class << self
      def dump(map, io_or_path)
        bytes = dump_bytes(map)
        if io_or_path.is_a?(String)
          File.binwrite(io_or_path, bytes)
        else
          io_or_path.write(bytes)
        end
      end

      def load(io_or_path)
        bytes =
          if io_or_path.is_a?(String)
            File.binread(io_or_path)
          else
            io_or_path.read
          end
        load_bytes(bytes)
      end

      def dump_bytes(map)
        payload = {
          'schema_version' => map.schema_version,
          'generated_at' => to_iso8601(map.generated_at),
          'commit_sha' => map.commit_sha,
          'branch' => map.branch,
          'collector' => map.collector,
          'known_spec_files' => map.known_spec_files.to_a.sort,
          'index' => map.index.transform_values { |specs| specs.to_a.sort },
        }

        io = StringIO.new
        io.set_encoding(Encoding::BINARY)
        gz = Zlib::GzipWriter.new(io)
        gz.write(JSON.generate(payload))
        gz.close
        io.string
      end

      def load_bytes(bytes)
        io = StringIO.new(bytes)
        gz = Zlib::GzipReader.new(io)
        json = gz.read
        gz.close

        data = JSON.parse(json)

        begin
          if data['schema_version'] != Map::SCHEMA_VERSION
            raise SchemaVersionError, "unsupported schema_version: #{data['schema_version'].inspect}"
          end

          Map.new(
            schema_version: data['schema_version'],
            generated_at: Time.parse(data['generated_at']),
            commit_sha: data['commit_sha'],
            branch: data['branch'],
            collector: data['collector'],
            known_spec_files: data['known_spec_files'],
            index: data['index']
          )
        rescue TypeError, NoMethodError, ArgumentError => e
          # Missing or malformed fields (nil generated_at, non-hash index, ...)
          raise MapFormatError, "malformed map payload: #{e.message}"
        end
      end

      private

      def to_iso8601(generated_at)
        time = generated_at.is_a?(String) ? Time.parse(generated_at) : generated_at
        # getutc (not utc/gmtime) so the caller's Time object is not mutated
        time.getutc.iso8601
      end
    end
  end
end
