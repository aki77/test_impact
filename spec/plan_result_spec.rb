# frozen_string_literal: true

RSpec.describe TestImpact::PlanResult do
  describe ".all" do
    it "builds a result with mode :all, no specs, and the given reason" do
      result = described_class.all("uncovered file changed: app/models/user.rb")

      expect(result.mode).to eq(:all)
      expect(result.spec_files).to eq([])
      expect(result.reason).to eq("uncovered file changed: app/models/user.rb")
    end
  end

  describe ".partial" do
    it "builds a result with mode :partial and a sorted, deduped spec list" do
      result = described_class.partial(["spec/b_spec.rb", "spec/a_spec.rb", "spec/a_spec.rb"])

      expect(result.mode).to eq(:partial)
      expect(result.spec_files).to eq(["spec/a_spec.rb", "spec/b_spec.rb"])
      expect(result.reason).to be_nil
    end

    it "accepts a Set and sorts it" do
      result = described_class.partial(Set["spec/b_spec.rb", "spec/a_spec.rb"])

      expect(result.spec_files).to eq(["spec/a_spec.rb", "spec/b_spec.rb"])
    end

    it "falls back to mode :none when given no spec files" do
      result = described_class.partial([])

      expect(result.mode).to eq(:none)
      expect(result.spec_files).to eq([])
      expect(result.reason).to be_nil
    end
  end

  describe "#==" do
    it "compares mode, spec_files, and reason" do
      a = described_class.partial(["spec/a_spec.rb"])
      b = described_class.partial(["spec/a_spec.rb"])
      c = described_class.partial(["spec/b_spec.rb"])

      expect(a).to eq(b)
      expect(a).not_to eq(c)
    end
  end
end
