# frozen_string_literal: true

RSpec.describe TestImpact::Planner do
  # Relative to now: Planner#staleness_reason compares against Time.now, so a
  # fixed date here would turn into a time bomb once max_age_days elapsed.
  let(:base_time) { Time.now.utc }

  def build_map(**overrides)
    TestImpact::Map.build(
      commit_sha: 'base_sha',
      branch: 'main',
      collector: { 'backend' => 'ddcov' },
      generated_at: base_time,
      known_spec_files: ['spec/models/user_spec.rb'],
      index: { 'app/models/user.rb' => ['spec/models/user_spec.rb'] },
      **overrides
    )
  end

  def build_config(**overrides)
    TestImpact::Config.new(
      {
        'base' => 'origin/main',
        'max_age_days' => 7,
        'always_run' => [],
        'global_files' => TestImpact::Config::DEFAULT_GLOBAL_FILES
      }.merge(overrides)
    )
  end

  def stub_git(merge_base: 'base_sha', in_history: true, changed_files: [])
    git = instance_double(TestImpact::Git)
    allow(git).to receive(:merge_base).and_return(merge_base)
    allow(git).to receive(:in_history?).and_return(in_history)
    allow(git).to receive(:changed_files).and_return(changed_files)
    git
  end

  describe 'map validity (branch a)' do
    it 'falls back to all when map is nil' do
      planner = described_class.new(map: nil, config: build_config, git: stub_git)

      result = planner.plan

      expect(result.mode).to eq(:all)
    end

    it 'falls back to all when map is empty' do
      map = build_map(index: {})
      planner = described_class.new(map:, config: build_config, git: stub_git)

      result = planner.plan

      expect(result.mode).to eq(:all)
    end

    it 'falls back to all when the map backend is invalid (null)' do
      map = build_map(collector: { 'backend' => 'null' })
      planner = described_class.new(map:, config: build_config, git: stub_git)

      result = planner.plan

      expect(result.mode).to eq(:all)
    end
  end

  describe 'staleness (branch b)' do
    it 'falls back to all when generated_at is older than max_age_days' do
      map = build_map(generated_at: Time.now - (8 * 86_400))
      planner = described_class.new(map:, config: build_config(max_age_days: 7), git: stub_git)

      result = planner.plan

      expect(result.mode).to eq(:all)
      expect(result.reason).to match(/max_age_days/)
    end

    it 'does not fall back to all when generated_at is within max_age_days' do
      map = build_map(generated_at: Time.now - (1 * 86_400), commit_sha: 'base_sha')
      git = stub_git(changed_files: [])
      planner = described_class.new(map:, config: build_config(max_age_days: 7), git:)

      result = planner.plan

      expect(result.mode).not_to eq(:all)
    end

    it "falls back to all when the map's commit_sha is not found in history" do
      map = build_map(generated_at: Time.now, commit_sha: 'missing_sha')
      git = stub_git(in_history: false)
      planner = described_class.new(map:, config: build_config, git:)

      result = planner.plan

      expect(result.mode).to eq(:all)
      expect(result.reason).to match(/missing_sha/)
    end
  end

  describe 'merge-base failure (branch c)' do
    it 'falls back to all when merge_base returns nil, mentioning fetch-depth' do
      map = build_map
      git = stub_git(merge_base: nil)
      planner = described_class.new(map:, config: build_config, git:)

      result = planner.plan

      expect(result.mode).to eq(:all)
      expect(result.reason).to match(/fetch-depth/)
    end

    it 'falls back to all when the diff itself cannot be computed' do
      map = build_map
      git = stub_git(changed_files: nil)
      planner = described_class.new(map:, config: build_config, git:)

      result = planner.plan

      expect(result.mode).to eq(:all)
      expect(result.reason).to match(/could not compute git diff/)
    end
  end

  describe 'change classification (branch d)' do
    context 'global files' do
      it 'falls back to all when a glob-matched global file changed (config/**/*)' do
        # The changed file is covered by the map, so only the global_files glob
        # (not the uncovered-file fallback) can produce this reason.
        map = build_map(index: { 'config/application.rb' => ['spec/models/user_spec.rb'] })
        git = stub_git(changed_files: [{ status: 'M', path: 'config/application.rb' }])
        planner = described_class.new(map:, config: build_config, git:)

        result = planner.plan

        expect(result.mode).to eq(:all)
        expect(result.reason).to eq('global file changed: config/application.rb')
      end

      it 'falls back to all when a global file is renamed away from its global location' do
        map = build_map(index: { 'config/settings.rb' => ['spec/config_spec.rb'] })
        git = stub_git(
          changed_files: [{ status: 'R', path: 'lib/settings.rb', old_path: 'config/settings.rb' }]
        )
        planner = described_class.new(map:, config: build_config, git:)

        result = planner.plan

        expect(result.mode).to eq(:all)
        expect(result.reason).to eq('global file changed: config/settings.rb')
      end

      it 'matches global file globs for deeply nested files (config/**/*)' do
        map = build_map(index: { 'config/environments/production.rb' => ['spec/models/user_spec.rb'] })
        git = stub_git(changed_files: [{ status: 'M', path: 'config/environments/production.rb' }])
        planner = described_class.new(map:, config: build_config, git:)

        result = planner.plan

        expect(result.mode).to eq(:all)
        expect(result.reason).to eq('global file changed: config/environments/production.rb')
      end

      it 'falls back to all when an exact-match global file changed (Gemfile)' do
        map = build_map
        git = stub_git(changed_files: [{ status: 'M', path: 'Gemfile' }])
        planner = described_class.new(map:, config: build_config, git:)

        result = planner.plan

        expect(result.mode).to eq(:all)
        expect(result.reason).to match(/Gemfile/)
      end
    end

    context 'spec files' do
      it 'always runs an added spec file' do
        map = build_map
        git = stub_git(changed_files: [{ status: 'A', path: 'spec/paths_spec.rb' }])
        planner = described_class.new(map:, config: build_config, git:)

        result = planner.plan

        expect(result.mode).to eq(:partial)
        expect(result.spec_files).to include('spec/paths_spec.rb')
      end

      it 'runs a modified spec file itself (spec files are never indexed as sources)' do
        map = build_map
        git = stub_git(changed_files: [{ status: 'M', path: 'spec/paths_spec.rb' }])
        planner = described_class.new(map:, config: build_config, git:)

        result = planner.plan

        expect(result.mode).to eq(:partial)
        expect(result.spec_files).to eq(['spec/paths_spec.rb'])
      end

      it 'excludes a deleted spec file from the run' do
        map = build_map
        git = stub_git(changed_files: [{ status: 'D', path: 'spec/models/gone_spec.rb' }])
        planner = described_class.new(map:, config: build_config, git:)

        result = planner.plan

        expect(result.mode).to eq(:none)
      end

      it "treats a renamed spec's old path as deleted and new path as added" do
        map = build_map
        git = stub_git(
          changed_files: [{ status: 'R', path: 'spec/paths_spec.rb', old_path: 'spec/models/old_name_spec.rb' }]
        )
        planner = described_class.new(map:, config: build_config, git:)

        result = planner.plan

        expect(result.mode).to eq(:partial)
        expect(result.spec_files).to eq(['spec/paths_spec.rb'])
      end
    end

    context 'view files' do
      it 'adds the covered specs for a covered, modified view file' do
        map = build_map(index: { 'app/views/users/show.html.erb' => ['spec/paths_spec.rb'] })
        git = stub_git(changed_files: [{ status: 'M', path: 'app/views/users/show.html.erb' }])
        planner = described_class.new(map:, config: build_config, git:)

        result = planner.plan

        expect(result.mode).to eq(:partial)
        expect(result.spec_files).to include('spec/paths_spec.rb')
      end

      it 'falls back to all for an uncovered, modified view file' do
        map = build_map
        git = stub_git(changed_files: [{ status: 'M', path: 'app/views/users/show.html.erb' }])
        planner = described_class.new(map:, config: build_config, git:)

        result = planner.plan

        expect(result.mode).to eq(:all)
        expect(result.reason).to match(/uncovered file changed/)
      end

      it 'pulls dependent specs for a deleted covered view file without forcing all' do
        map = build_map(index: { 'app/views/users/show.html.erb' => ['spec/config_spec.rb'] })
        git = stub_git(changed_files: [{ status: 'D', path: 'app/views/users/show.html.erb' }])
        planner = described_class.new(map:, config: build_config, git:)

        result = planner.plan

        expect(result.mode).to eq(:partial)
        expect(result.spec_files).to include('spec/config_spec.rb')
      end

      it 'falls back to all when an uncovered view file is deleted' do
        map = build_map
        git = stub_git(changed_files: [{ status: 'D', path: 'app/views/users/show.html.erb' }])
        planner = described_class.new(map:, config: build_config, git:)

        result = planner.plan

        expect(result.mode).to eq(:all)
        expect(result.reason).to match(/uncovered file changed/)
      end

      it "keeps the old path's dependents when a covered view file is renamed to another view" do
        map = build_map(index: { 'app/views/users/old_show.html.erb' => ['spec/config_spec.rb'] })
        git = stub_git(
          changed_files: [
            { status: 'R', path: 'app/views/users/show.html.erb', old_path: 'app/views/users/old_show.html.erb' }
          ]
        )
        planner = described_class.new(map:, config: build_config, git:)

        result = planner.plan

        expect(result.mode).to eq(:partial)
        expect(result.spec_files).to eq(['spec/config_spec.rb'])
      end

      it 'falls back to all when a view renamed to another view is uncovered on both sides' do
        map = build_map
        git = stub_git(
          changed_files: [
            { status: 'R', path: 'app/views/users/show.html.erb', old_path: 'app/views/users/old_show.html.erb' }
          ]
        )
        planner = described_class.new(map:, config: build_config, git:)

        result = planner.plan

        expect(result.mode).to eq(:all)
        expect(result.reason).to match(/uncovered file changed/)
      end

      it "keeps the old path's dependents when a covered view file is renamed to a .rb file" do
        map = build_map(index: { 'app/views/users/show.html.erb' => ['spec/config_spec.rb'] })
        git = stub_git(
          changed_files: [
            { status: 'R', path: 'lib/test_impact/show_presenter.rb', old_path: 'app/views/users/show.html.erb' }
          ]
        )
        planner = described_class.new(map:, config: build_config, git:)

        result = planner.plan

        expect(result.mode).to eq(:partial)
        expect(result.spec_files).to eq(['spec/config_spec.rb'])
      end

      it "keeps the old path's dependents when a covered view file is renamed to a non-tracked extension" do
        map = build_map(index: { 'app/views/users/show.html.erb' => ['spec/config_spec.rb'] })
        git = stub_git(
          changed_files: [{ status: 'R', path: 'docs/show.md', old_path: 'app/views/users/show.html.erb' }]
        )
        planner = described_class.new(map:, config: build_config, git:)

        result = planner.plan

        expect(result.mode).to eq(:partial)
        expect(result.spec_files).to eq(['spec/config_spec.rb'])
      end
    end

    context 'ruby files' do
      it 'adds the covered specs for a covered .rb file' do
        map = build_map(index: { 'lib/test_impact/paths.rb' => ['spec/paths_spec.rb'] })
        git = stub_git(changed_files: [{ status: 'M', path: 'lib/test_impact/paths.rb' }])
        planner = described_class.new(map:, config: build_config, git:)

        result = planner.plan

        expect(result.spec_files).to include('spec/paths_spec.rb')
      end

      it 'falls back to all for an uncovered .rb file' do
        map = build_map
        git = stub_git(changed_files: [{ status: 'M', path: 'lib/test_impact/unknown.rb' }])
        planner = described_class.new(map:, config: build_config, git:)

        result = planner.plan

        expect(result.mode).to eq(:all)
        expect(result.reason).to match(/uncovered file changed/)
      end

      it 'pulls dependent specs for a deleted covered source file without forcing all' do
        map = build_map(index: { 'lib/test_impact/gone.rb' => ['spec/config_spec.rb'] })
        git = stub_git(changed_files: [{ status: 'D', path: 'lib/test_impact/gone.rb' }])
        planner = described_class.new(map:, config: build_config, git:)

        result = planner.plan

        expect(result.mode).to eq(:partial)
        expect(result.spec_files).to include('spec/config_spec.rb')
      end

      it 'falls back to all when an uncovered source file is deleted' do
        map = build_map
        git = stub_git(changed_files: [{ status: 'D', path: 'lib/unknown_to_the_map.rb' }])
        planner = described_class.new(map:, config: build_config, git:)

        result = planner.plan

        expect(result.mode).to eq(:all)
        expect(result.reason).to eq('uncovered file changed: lib/unknown_to_the_map.rb')
      end

      it "keeps the old path's dependents when a covered source is renamed into a spec path" do
        map = build_map(index: { 'lib/user.rb' => ['spec/config_spec.rb'] })
        git = stub_git(
          changed_files: [{ status: 'R', path: 'spec/paths_spec.rb', old_path: 'lib/user.rb' }]
        )
        planner = described_class.new(map:, config: build_config, git:)

        result = planner.plan

        expect(result.mode).to eq(:partial)
        expect(result.spec_files).to contain_exactly('spec/paths_spec.rb', 'spec/config_spec.rb')
      end

      it "keeps the old path's dependents when a covered ruby file is renamed to a view extension" do
        map = build_map(index: { 'lib/user.rb' => ['spec/config_spec.rb'] })
        git = stub_git(
          changed_files: [{ status: 'R', path: 'app/views/user.html.erb', old_path: 'lib/user.rb' }]
        )
        planner = described_class.new(map:, config: build_config, git:)

        result = planner.plan

        expect(result.mode).to eq(:partial)
        expect(result.spec_files).to eq(['spec/config_spec.rb'])
      end

      it "keeps the old path's dependents when a covered ruby file is renamed to a non-ruby extension" do
        map = build_map(index: { 'lib/user.rb' => ['spec/config_spec.rb'] })
        git = stub_git(
          changed_files: [{ status: 'R', path: 'docs/user.md', old_path: 'lib/user.rb' }]
        )
        planner = described_class.new(map:, config: build_config, git:)

        result = planner.plan

        expect(result.mode).to eq(:partial)
        expect(result.spec_files).to eq(['spec/config_spec.rb'])
      end

      it "runs the old path's dependents for a realistic rename (new path not in the map)" do
        map = build_map(index: { 'lib/test_impact/old_name.rb' => ['spec/config_spec.rb'] })
        git = stub_git(
          changed_files: [{ status: 'R', path: 'lib/test_impact/paths.rb', old_path: 'lib/test_impact/old_name.rb' }]
        )
        planner = described_class.new(map:, config: build_config, git:)

        result = planner.plan

        expect(result.mode).to eq(:partial)
        expect(result.spec_files).to eq(['spec/config_spec.rb'])
      end

      it 'pulls dependent specs for the old path of a renamed source file' do
        map = build_map(
          index: {
            'lib/test_impact/old_name.rb' => ['spec/config_spec.rb'],
            'lib/test_impact/paths.rb' => ['spec/paths_spec.rb']
          }
        )
        git = stub_git(
          changed_files: [{ status: 'R', path: 'lib/test_impact/paths.rb', old_path: 'lib/test_impact/old_name.rb' }]
        )
        planner = described_class.new(map:, config: build_config, git:)

        result = planner.plan

        expect(result.spec_files).to include('spec/config_spec.rb')
        expect(result.spec_files).to include('spec/paths_spec.rb')
      end
    end

    context 'other non-ruby files' do
      it 'ignores documentation files not in global_files' do
        map = build_map
        git = stub_git(changed_files: [{ status: 'M', path: 'README.md' }])
        planner = described_class.new(map:, config: build_config, git:)

        result = planner.plan

        expect(result.mode).to eq(:none)
      end

      it 'falls back to all for an unknown extension not covered by global_files' do
        map = build_map
        git = stub_git(changed_files: [{ status: 'A', path: 'app/assets/data.bin' }])
        planner = described_class.new(map:, config: build_config, git:)

        result = planner.plan

        expect(result.mode).to eq(:all)
      end
    end
  end

  describe 'always_run (branch e)' do
    it 'unconditionally adds an always_run spec that exists on disk' do
      map = build_map(known_spec_files: ['spec/paths_spec.rb'])
      git = stub_git(changed_files: [])
      config = build_config(always_run: ['spec/paths_spec.rb'])
      planner = described_class.new(map:, config:, git:)

      result = planner.plan

      expect(result.spec_files).to include('spec/paths_spec.rb')
    end

    it 'does not add an always_run spec that no longer exists on disk' do
      map = build_map(known_spec_files: ['spec/models/deleted_long_ago_spec.rb'])
      git = stub_git(changed_files: [])
      config = build_config(always_run: ['spec/models/deleted_long_ago_spec.rb'])
      planner = described_class.new(map:, config:, git:)

      result = planner.plan

      expect(result.spec_files).not_to include('spec/models/deleted_long_ago_spec.rb')
    end
  end

  describe 'removing nonexistent files from the plan (branch f)' do
    it 'excludes a spec_files entry that does not exist on disk' do
      map = build_map
      git = stub_git(changed_files: [{ status: 'A', path: 'spec/models/ephemeral_spec.rb' }])
      planner = described_class.new(map:, config: build_config, git:)

      result = planner.plan

      expect(result.spec_files).not_to include('spec/models/ephemeral_spec.rb')
    end
  end

  describe '#plan base argument' do
    it 'passes the base override through to git.merge_base' do
      map = build_map
      git = stub_git(changed_files: [])
      expect(git).to receive(:merge_base).with('origin/develop').and_return('base_sha')
      planner = described_class.new(map:, config: build_config, git:)

      planner.plan(base: 'origin/develop')
    end

    it 'falls back to config.base when no override is given' do
      map = build_map
      git = stub_git(changed_files: [])
      expect(git).to receive(:merge_base).with('origin/main').and_return('base_sha')
      planner = described_class.new(map:, config: build_config(base: 'origin/main'), git:)

      planner.plan
    end
  end
end
