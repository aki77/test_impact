# frozen_string_literal: true

require "test_impact/version"
require "test_impact/paths"
require "test_impact/config"
require "test_impact/map"
require "test_impact/map_serializer"

module TestImpact
  class Error < StandardError; end
  class SchemaVersionError < Error; end
  class MapFormatError < Error; end
  class CoverageUnavailableError < Error; end
  class DatastoreError < Error; end

  class << self
    attr_accessor :recorder
  end
end

require "test_impact/collector/coverage_backend"
require "test_impact/recorder"
require "test_impact/git"
require "test_impact/plan_result"
require "test_impact/planner"
require "test_impact/datastore/base"
require "test_impact/datastore/github_client"
require "test_impact/datastore/local"
require "test_impact/datastore/artifact"
require "test_impact/datastore/branch"
require "test_impact/datastore/registry"
require "test_impact/cli"
