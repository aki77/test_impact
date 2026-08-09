# frozen_string_literal: true

require 'test_impact/collector/coverage_backend'

RSpec.describe TestImpact::Collector::CoverageBackend do
  let(:config) { TestImpact::Config.new }

  around do |example|
    original = ENV.fetch('TEST_IMPACT_REQUIRE_COVERAGE', nil)
    example.run
  ensure
    if original.nil?
      ENV.delete('TEST_IMPACT_REQUIRE_COVERAGE')
    else
      ENV['TEST_IMPACT_REQUIRE_COVERAGE'] = original
    end
  end

  context 'when the ddcov backend is available' do
    let(:ddcov) { instance_double(TestImpact::Collector::DdcovBackend) }

    before do
      allow(TestImpact::Collector::DdcovBackend).to receive(:unavailable_reason).and_return(nil)
      allow(TestImpact::Collector::DdcovBackend).to receive(:new).with(config).and_return(ddcov)
    end

    it 'returns a ddcov backend' do
      expect(described_class.build(config)).to be(ddcov)
    end

    it 'does not warn' do
      expect($stderr).not_to receive(:puts)
      described_class.build(config)
    end

    it 'does not raise' do
      expect { described_class.build(config) }.not_to raise_error
    end
  end

  context 'when the ddcov backend is unavailable' do
    let(:reason) { LoadError.new('cannot load such file -- datadog_ci_native') }

    before do
      allow(TestImpact::Collector::DdcovBackend).to receive(:unavailable_reason).and_return(reason)
      allow($stderr).to receive(:puts)
    end

    it 'raises CoverageUnavailableError by default' do
      expect { described_class.build(config) }.to raise_error(TestImpact::CoverageUnavailableError)
    end

    it 'includes the cause of the failure in the message' do
      expect { described_class.build(config) }
        .to raise_error(TestImpact::CoverageUnavailableError,
                        /LoadError: cannot load such file -- datadog_ci_native/)
    end

    it 'points at the opt-out in the message' do
      expect { described_class.build(config) }
        .to raise_error(TestImpact::CoverageUnavailableError, /TEST_IMPACT_REQUIRE_COVERAGE=0/)
    end

    context 'when TEST_IMPACT_REQUIRE_COVERAGE is 1' do
      before { ENV['TEST_IMPACT_REQUIRE_COVERAGE'] = '1' }

      it 'raises CoverageUnavailableError' do
        expect { described_class.build(config) }.to raise_error(TestImpact::CoverageUnavailableError)
      end
    end

    context 'when TEST_IMPACT_REQUIRE_COVERAGE opts out' do
      before { ENV['TEST_IMPACT_REQUIRE_COVERAGE'] = '0' }

      it 'falls back to the null backend' do
        expect(described_class.build(config)).to be_a(TestImpact::Collector::NullBackend)
      end

      it 'warns on stderr' do
        described_class.build(config)
        expect($stderr).to have_received(:puts).with(/coverage backend unavailable/)
      end

      # A misspelled opt-out would fail the collection job, and only on the
      # day the backend actually breaks -- so accept the usual spellings.
      ['false', 'no', 'off', 'FALSE', 'Off', ' 0 '].each do |value|
        it "accepts #{value.inspect}" do
          ENV['TEST_IMPACT_REQUIRE_COVERAGE'] = value
          expect(described_class.build(config)).to be_a(TestImpact::Collector::NullBackend)
        end
      end
    end
  end
end
