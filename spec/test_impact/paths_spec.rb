# frozen_string_literal: true

RSpec.describe TestImpact::Paths do
  describe '.repo_root' do
    it "returns this gem repository's root as an absolute path" do
      root = described_class.repo_root

      expect(root).to be_a(String)
      expect(File).to be_absolute_path(root)
      expect(File).to exist(File.join(root, 'test_impact.gemspec'))
    end
  end

  describe '.relative and .absolute' do
    it 'round-trips an absolute path under repo_root' do
      abs_path = File.join(described_class.repo_root, 'lib', 'test_impact.rb')

      relative = described_class.relative(abs_path)

      expect(relative).to eq('lib/test_impact.rb')
      expect(described_class.absolute(relative)).to eq(abs_path)
    end

    it 'uses forward slashes regardless of platform' do
      abs_path = File.join(described_class.repo_root, 'lib', 'test_impact', 'cli.rb')

      relative = described_class.relative(abs_path)

      expect(relative).not_to include('\\')
      expect(relative).to eq('lib/test_impact/cli.rb')
    end
  end
end
