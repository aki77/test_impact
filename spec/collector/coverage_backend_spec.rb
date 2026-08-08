# frozen_string_literal: true

require "test_impact/collector/coverage_backend"

RSpec.describe TestImpact::Collector::CoverageBackend do
  let(:config) { TestImpact::Config.new }

  around do |example|
    original = ENV.fetch("TEST_IMPACT_REQUIRE_COVERAGE", nil)
    example.run
  ensure
    if original.nil?
      ENV.delete("TEST_IMPACT_REQUIRE_COVERAGE")
    else
      ENV["TEST_IMPACT_REQUIRE_COVERAGE"] = original
    end
  end

  context "when the ddcov backend is available" do
    let(:ddcov) { instance_double(TestImpact::Collector::DdcovBackend) }

    before do
      allow(TestImpact::Collector::DdcovBackend).to receive(:available?).and_return(true)
      allow(TestImpact::Collector::DdcovBackend).to receive(:new).with(config).and_return(ddcov)
    end

    it "returns a ddcov backend" do
      expect(described_class.build(config)).to be(ddcov)
    end

    it "does not warn" do
      expect($stderr).not_to receive(:puts)
      described_class.build(config)
    end
  end

  context "when the ddcov backend is unavailable" do
    before do
      allow(TestImpact::Collector::DdcovBackend).to receive(:available?).and_return(false)
      allow($stderr).to receive(:puts)
    end

    it "falls back to the null backend" do
      expect(described_class.build(config)).to be_a(TestImpact::Collector::NullBackend)
    end

    it "warns on stderr" do
      described_class.build(config)
      expect($stderr).to have_received(:puts).with(/coverage backend unavailable/)
    end

    context "when TEST_IMPACT_REQUIRE_COVERAGE is 1" do
      before { ENV["TEST_IMPACT_REQUIRE_COVERAGE"] = "1" }

      it "raises CoverageUnavailableError" do
        expect { described_class.build(config) }.to raise_error(TestImpact::CoverageUnavailableError)
      end
    end

    context "when TEST_IMPACT_REQUIRE_COVERAGE is set to something else" do
      before { ENV["TEST_IMPACT_REQUIRE_COVERAGE"] = "0" }

      it "still falls back to the null backend" do
        expect(described_class.build(config)).to be_a(TestImpact::Collector::NullBackend)
      end
    end
  end
end
