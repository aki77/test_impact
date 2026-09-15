# frozen_string_literal: true

RSpec.describe TestImpact::PathMatcher do
  describe '.match?' do
    it 'matches across directory levels with "**"' do
      expect(described_class.match?('config/**/*', 'config/a/b.rb')).to be(true)
    end

    it 'expands brace alternatives' do
      expect(described_class.match?('*.{yml,yaml}', 'a.yaml')).to be(true)
    end

    it 'matches a dotfile with an explicit extension' do
      expect(described_class.match?('**/*.yml', '.rubocop.yml')).to be(true)
    end

    it 'matches a dotfile with a bare wildcard' do
      expect(described_class.match?('**/*', '.rubocop.yml')).to be(true)
    end

    it 'does not let a single "*" cross a directory separator' do
      expect(described_class.match?('*.md', 'docs/a.md')).to be(false)
    end
  end

  describe '.any_match?' do
    it 'returns true when any pattern matches' do
      expect(described_class.any_match?(['lib/**/*', 'docs/**/*'], 'docs/a.md')).to be(true)
    end

    it 'returns false when no pattern matches' do
      expect(described_class.any_match?(['lib/**/*'], 'docs/a.md')).to be(false)
    end

    it 'returns false for nil' do
      expect(described_class.any_match?(nil, 'docs/a.md')).to be(false)
    end

    it 'returns false for an empty list' do
      expect(described_class.any_match?([], 'docs/a.md')).to be(false)
    end
  end

  describe '.glob?' do
    it 'is false for a directory prefix' do
      expect(described_class.glob?('vendor/')).to be(false)
    end

    it 'is false for another directory prefix' do
      expect(described_class.glob?('tmp/')).to be(false)
    end

    it 'is false for a plain file name' do
      expect(described_class.glob?('LICENSE')).to be(false)
    end

    it 'is true for a wildcard pattern' do
      expect(described_class.glob?('**/*.rb')).to be(true)
    end

    it 'is true for a brace pattern' do
      expect(described_class.glob?('a{b,c}.rb')).to be(true)
    end

    it 'is true for a single-character wildcard' do
      expect(described_class.glob?('a?.rb')).to be(true)
    end

    it 'is true for a character class' do
      expect(described_class.glob?('a[0-9].rb')).to be(true)
    end
  end
end
