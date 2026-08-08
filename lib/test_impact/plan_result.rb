# frozen_string_literal: true

module TestImpact
  class PlanResult
    attr_reader :mode, :spec_files, :reason

    def self.all(reason)
      new(mode: :all, spec_files: [], reason: reason)
    end

    def self.partial(spec_files)
      spec_files = spec_files.to_a.uniq.sort
      new(mode: spec_files.empty? ? :none : :partial, spec_files: spec_files, reason: nil)
    end

    def initialize(mode:, spec_files:, reason:)
      @mode = mode
      @spec_files = spec_files
      @reason = reason
    end

    def ==(other)
      other.is_a?(PlanResult) &&
        mode == other.mode &&
        spec_files == other.spec_files &&
        reason == other.reason
    end
    alias eql? ==

    def hash
      [mode, spec_files, reason].hash
    end
  end
end
