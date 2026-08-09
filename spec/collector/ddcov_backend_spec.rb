# frozen_string_literal: true

require "test_impact/collector/ddcov_backend"

RSpec.describe TestImpact::Collector::DdcovBackend do
  # The memoization is process-wide, so a probe forced here would otherwise
  # leak into every later caller (including the real collector).
  around do |example|
    described_class.reset_memoization!
    example.run
  ensure
    described_class.reset_memoization!
  end

  # Verified against the real class when the native extension is present;
  # falls back to a plain double where it can't be loaded, so this spec still
  # runs on platforms ddcov does not ship for.
  let(:probe) do
    if ddcov_class
      instance_double(ddcov_class, start: nil, stop: {})
    else
      double(start: nil, stop: {})
    end
  end

  let(:ddcov_class) do
    described_class.load_ddcov_class!
  rescue LoadError, StandardError
    nil
  end

  describe ".available?" do
    context "when probing fails" do
      let(:error) { LoadError.new("cannot load such file -- datadog_ci_native") }

      before { allow(described_class).to receive(:build_instance).and_raise(error) }

      it "returns false" do
        expect(described_class.available?(use_allocation_tracing: true)).to be(false)
      end

      it "keeps the causing exception" do
        expect(described_class.unavailable_reason(use_allocation_tracing: true)).to be(error)
      end

      it "probes once and reuses the result" do
        2.times { described_class.available?(use_allocation_tracing: true) }
        expect(described_class).to have_received(:build_instance).once
      end
    end

    context "when probing succeeds" do
      before { allow(described_class).to receive(:build_instance).and_return(probe) }

      it "returns true" do
        expect(described_class.available?(use_allocation_tracing: true)).to be(true)
      end

      it "records no reason" do
        expect(described_class.unavailable_reason(use_allocation_tracing: true)).to be_nil
      end
    end

    it "probes each allocation tracing mode separately" do
      allow(described_class).to receive(:build_instance)
        .with(hash_including(use_allocation_tracing: true)).and_raise(LoadError, "boom")
      allow(described_class).to receive(:build_instance)
        .with(hash_including(use_allocation_tracing: false)).and_return(probe)

      expect(described_class.available?(use_allocation_tracing: true)).to be(false)
      expect(described_class.available?(use_allocation_tracing: false)).to be(true)
    end
  end

  describe ".reset_memoization!" do
    it "forces the next call to probe again" do
      allow(described_class).to receive(:build_instance).and_raise(LoadError, "boom")
      expect(described_class.available?(use_allocation_tracing: true)).to be(false)

      described_class.reset_memoization!
      allow(described_class).to receive(:build_instance).and_return(probe)

      expect(described_class.available?(use_allocation_tracing: true)).to be(true)
      expect(described_class.unavailable_reason(use_allocation_tracing: true)).to be_nil
    end
  end

  describe ".allocation_tracing?" do
    it "is true when the collector config enables it" do
      config = TestImpact::Config.new("collector" => { "allocation_tracing" => true })
      expect(described_class.allocation_tracing?(config)).to be(true)
    end

    it "is false when the collector config disables it" do
      config = TestImpact::Config.new("collector" => { "allocation_tracing" => false })
      expect(described_class.allocation_tracing?(config)).to be(false)
    end
  end
end
