# frozen_string_literal: true

require 'test_impact/version'
require 'test_impact/paths'
require 'test_impact/path_matcher'
require 'test_impact/config'
require 'test_impact/map'
require 'test_impact/map_serializer'

# Test Impact Analysis for Ruby: records which source files each spec touches,
# then plans a minimal spec set from a git diff.
module TestImpact
  class Error < StandardError; end
  class SchemaVersionError < Error; end
  class MapFormatError < Error; end
  class CoverageUnavailableError < Error; end

  class << self
    attr_accessor :recorder
  end
end

require 'test_impact/collector/coverage_backend'
require 'test_impact/recorder'
require 'test_impact/git'
require 'test_impact/plan_result'
require 'test_impact/planner'
require 'test_impact/cli'
