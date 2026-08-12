# frozen_string_literal: true

RSpec.describe TestImpact::Map do
  let(:base_time) { Time.utc(2026, 8, 8, 0, 0, 0) }

  def build_map(**overrides)
    described_class.build(
      commit_sha: 'abc123',
      branch: 'main',
      collector: { 'backend' => 'ddcov' },
      generated_at: base_time,
      known_spec_files: ['spec/models/user_spec.rb'],
      index: { 'app/models/user.rb' => ['spec/models/user_spec.rb'] },
      **overrides
    )
  end

  describe '.build' do
    it 'constructs a map with schema_version fixed to 1' do
      map = build_map

      expect(map.schema_version).to eq(1)
      expect(map.commit_sha).to eq('abc123')
      expect(map.branch).to eq('main')
      expect(map.known_spec_files).to eq(Set['spec/models/user_spec.rb'])
      expect(map.index).to eq({ 'app/models/user.rb' => Set['spec/models/user_spec.rb'] })
    end
  end

  describe '#merge' do
    it 'keeps the null backend when the earlier map had one' do
      null_map = build_map(collector: { 'backend' => 'null' })
      ddcov_map = build_map(collector: { 'backend' => 'ddcov' })

      expect(null_map.merge(ddcov_map).valid_backend?).to be(false)
    end

    it 'keeps the null backend when the later map had one' do
      null_map = build_map(collector: { 'backend' => 'null' })
      ddcov_map = build_map(collector: { 'backend' => 'ddcov' })

      expect(ddcov_map.merge(null_map).valid_backend?).to be(false)
    end

    it 'unions known_spec_files and index without mutating the originals' do
      map_a = build_map(
        known_spec_files: ['spec/models/user_spec.rb'],
        index: { 'app/models/user.rb' => ['spec/models/user_spec.rb'] }
      )
      map_b = build_map(
        generated_at: base_time + 10,
        known_spec_files: ['spec/models/post_spec.rb'],
        index: {
          'app/models/user.rb' => ['spec/models/post_spec.rb'],
          'app/models/post.rb' => ['spec/models/post_spec.rb'],
        }
      )

      merged = map_a.merge(map_b)

      expect(merged.known_spec_files).to eq(Set['spec/models/user_spec.rb', 'spec/models/post_spec.rb'])
      expect(merged.index).to eq(
        'app/models/user.rb' => Set['spec/models/user_spec.rb', 'spec/models/post_spec.rb'],
        'app/models/post.rb' => Set['spec/models/post_spec.rb']
      )
      expect(map_a.known_spec_files).to eq(Set['spec/models/user_spec.rb'])
      expect(map_a.index).to eq('app/models/user.rb' => Set['spec/models/user_spec.rb'])
    end

    it 'is idempotent when merging the same map twice' do
      map_a = build_map
      map_b = build_map(generated_at: base_time + 10, known_spec_files: ['spec/models/post_spec.rb'])

      merged_once = map_a.merge(map_b)
      merged_twice = merged_once.merge(map_b)

      expect(merged_twice).to eq(merged_once)
    end

    it "adopts the newer map's commit_sha, branch, and collector" do
      map_a = build_map(commit_sha: 'abc123', branch: 'main', collector: { 'backend' => 'ddcov' })
      map_b = build_map(commit_sha: 'def456',
                        branch: 'feature',
                        collector: { 'backend' => 'null' },
                        generated_at: base_time + 10)

      merged = map_a.merge(map_b)

      expect(merged.commit_sha).to eq('def456')
      expect(merged.branch).to eq('feature')
      expect(merged.collector).to eq({ 'backend' => 'null' })
    end

    it "adopts the newer map's metadata regardless of merge order" do
      newer = build_map(commit_sha: 'abc123', branch: 'main', generated_at: base_time + 10)
      older = build_map(commit_sha: 'def456', branch: 'feature', generated_at: base_time)

      merged = newer.merge(older)

      expect(merged.generated_at).to eq(base_time + 10)
      expect(merged.commit_sha).to eq('abc123')
      expect(merged.branch).to eq('main')
    end

    it 'adopts the later generated_at' do
      map_a = build_map(generated_at: base_time)
      map_b = build_map(generated_at: base_time - 100)

      merged = map_a.merge(map_b)

      expect(merged.generated_at).to eq(base_time)
    end
  end

  describe '#commit_sha_mismatch?' do
    it 'detects when commit_sha differs between maps' do
      map_a = build_map(commit_sha: 'abc123')
      map_b = build_map(commit_sha: 'def456')

      expect(map_a.commit_sha_mismatch?(map_b)).to be(true)
      expect(map_a.commit_sha_mismatch?(build_map(commit_sha: 'abc123'))).to be(false)
    end
  end

  describe '#specs_for' do
    it 'returns the spec set for a covered source path' do
      map = build_map

      expect(map.specs_for('app/models/user.rb')).to eq(Set['spec/models/user_spec.rb'])
    end

    it 'returns an empty set for an uncovered source path' do
      map = build_map

      expect(map.specs_for('app/models/unknown.rb')).to eq(Set.new)
    end
  end

  describe '#covered?' do
    it 'returns true for a known source path' do
      expect(build_map.covered?('app/models/user.rb')).to be(true)
    end

    it 'returns false for an unknown source path' do
      expect(build_map.covered?('app/models/unknown.rb')).to be(false)
    end
  end

  describe '#spec_count' do
    it 'counts the union of specs across all covered source files' do
      map = build_map(
        index: {
          'app/models/user.rb' => ['spec/models/user_spec.rb'],
          'app/models/post.rb' => ['spec/models/user_spec.rb', 'spec/models/post_spec.rb'],
        }
      )

      expect(map.spec_count).to eq(2)
    end

    it 'returns 0 when the index is empty' do
      expect(build_map(index: {}).spec_count).to eq(0)
    end
  end

  describe '#empty?' do
    it 'returns true when the index has no entries' do
      map = build_map(index: {})

      expect(map.empty?).to be(true)
    end

    it 'returns false when the index has entries' do
      expect(build_map.empty?).to be(false)
    end
  end

  describe '#valid_backend?' do
    it 'returns true when backend is not null' do
      expect(build_map(collector: { 'backend' => 'ddcov' }).valid_backend?).to be(true)
    end

    it 'returns false when backend is the null backend' do
      expect(build_map(collector: { 'backend' => 'null' }).valid_backend?).to be(false)
    end

    it 'returns true when backend key is absent' do
      expect(build_map(collector: {}).valid_backend?).to be(true)
    end
  end

  describe '#==' do
    it 'returns true for maps with identical attributes' do
      other = build_map

      expect(build_map).to eq(other)
    end

    it 'returns false when index differs' do
      other = build_map(index: { 'app/models/other.rb' => ['spec/models/other_spec.rb'] })

      expect(build_map).not_to eq(other)
    end
  end
end
