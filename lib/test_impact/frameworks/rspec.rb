# frozen_string_literal: true

return unless ENV['TEST_IMPACT_COLLECT'] == '1'

require 'test_impact'
require 'test_impact/collector/coverage_backend'
require 'test_impact/recorder'

test_impact_config = TestImpact::Config.load
TestImpact.recorder = TestImpact::Recorder.new(
  backend: TestImpact::Collector::CoverageBackend.build(test_impact_config),
  config: test_impact_config
)

RSpec.configure do |config|
  config.prepend_before(:each) { TestImpact.recorder.start_example }

  config.append_after(:each) do |example|
    TestImpact.recorder.finish_example(example.metadata[:absolute_file_path])
  end

  config.after(:suite) do
    TestImpact.recorder.record_known_spec_files(RSpec.configuration.files_to_run)
    TestImpact.recorder.write_part
  end
end

at_exit { TestImpact.recorder&.write_part }
