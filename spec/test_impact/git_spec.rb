# frozen_string_literal: true

RSpec.describe TestImpact::Git do
  describe '#merge_base' do
    it 'returns the merge-base sha between base_ref and HEAD' do
      GitSandbox.create do |dir|
        GitSandbox.write(dir, 'a.rb', '1')
        base_sha = GitSandbox.commit(dir, 'init')
        GitSandbox.run(dir, 'branch', 'feature')
        GitSandbox.write(dir, 'a.rb', '2')
        GitSandbox.commit(dir, 'on main')
        GitSandbox.run(dir, 'checkout', '-q', 'feature')

        git = described_class.new(repo_root: dir)

        expect(git.merge_base('main')).to eq(base_sha)
      end
    end

    it 'returns nil when the ref does not exist' do
      GitSandbox.create do |dir|
        GitSandbox.write(dir, 'a.rb', '1')
        GitSandbox.commit(dir, 'init')

        git = described_class.new(repo_root: dir)

        expect(git.merge_base('origin/does-not-exist')).to be_nil
      end
    end
  end

  describe '#changed_files' do
    it 'reports an added file with status A' do
      GitSandbox.create do |dir|
        GitSandbox.write(dir, 'a.rb', '1')
        base_sha = GitSandbox.commit(dir, 'init')
        GitSandbox.write(dir, 'b.rb', '1')
        GitSandbox.commit(dir, 'add b')

        git = described_class.new(repo_root: dir)

        expect(git.changed_files(base_sha)).to eq([{ status: 'A', path: 'b.rb' }])
      end
    end

    it 'reports a modified file with status M' do
      GitSandbox.create do |dir|
        GitSandbox.write(dir, 'a.rb', '1')
        base_sha = GitSandbox.commit(dir, 'init')
        GitSandbox.write(dir, 'a.rb', '2')
        GitSandbox.commit(dir, 'modify a')

        git = described_class.new(repo_root: dir)

        expect(git.changed_files(base_sha)).to eq([{ status: 'M', path: 'a.rb' }])
      end
    end

    it 'reports a deleted file with status D' do
      GitSandbox.create do |dir|
        GitSandbox.write(dir, 'a.rb', '1')
        base_sha = GitSandbox.commit(dir, 'init')
        FileUtils.rm(File.join(dir, 'a.rb'))
        GitSandbox.commit(dir, 'delete a')

        git = described_class.new(repo_root: dir)

        expect(git.changed_files(base_sha)).to eq([{ status: 'D', path: 'a.rb' }])
      end
    end

    it 'reports a renamed file with status R and both paths' do
      GitSandbox.create do |dir|
        GitSandbox.write(dir, 'a.rb', '1' * 50)
        base_sha = GitSandbox.commit(dir, 'init')
        GitSandbox.run(dir, 'mv', 'a.rb', 'b.rb')
        GitSandbox.commit(dir, 'rename a to b')

        git = described_class.new(repo_root: dir)

        expect(git.changed_files(base_sha)).to eq([{ status: 'R', path: 'b.rb', old_path: 'a.rb' }])
      end
    end

    it 'normalizes a copy (C) to A' do
      GitSandbox.create do |dir|
        GitSandbox.write(dir, 'a.rb', '1' * 50)
        base_sha = GitSandbox.commit(dir, 'init')
        FileUtils.cp(File.join(dir, 'a.rb'), File.join(dir, 'b.rb'))
        GitSandbox.commit(dir, 'copy a to b')

        git = described_class.new(repo_root: dir)
        changes = git.changed_files(base_sha)

        expect(changes).to eq([{ status: 'A', path: 'b.rb' }])
      end
    end

    it 'returns nil when the sha cannot be diffed' do
      GitSandbox.create do |dir|
        GitSandbox.write(dir, 'a.rb', '1')
        GitSandbox.commit(dir, 'init')

        git = described_class.new(repo_root: dir)

        expect(git.changed_files('0000000000000000000000000000000000000000')).to be_nil
      end
    end
  end

  describe '#in_history?' do
    it 'returns true for a commit reachable from the ref' do
      GitSandbox.create do |dir|
        GitSandbox.write(dir, 'a.rb', '1')
        sha = GitSandbox.commit(dir, 'init')

        git = described_class.new(repo_root: dir)

        expect(git.in_history?(sha, 'HEAD')).to be(true)
      end
    end

    it 'returns false for an unknown sha' do
      GitSandbox.create do |dir|
        GitSandbox.write(dir, 'a.rb', '1')
        GitSandbox.commit(dir, 'init')

        git = described_class.new(repo_root: dir)

        expect(git.in_history?('0000000000000000000000000000000000000000', 'HEAD')).to be(false)
      end
    end

    it 'returns false for a commit that exists but is not reachable from the ref' do
      GitSandbox.create do |dir|
        GitSandbox.write(dir, 'a.rb', '1')
        GitSandbox.commit(dir, 'init')
        GitSandbox.run(dir, 'switch', '-q', '-c', 'side')
        GitSandbox.write(dir, 'b.rb', '1')
        side_sha = GitSandbox.commit(dir, 'side commit')
        GitSandbox.run(dir, 'switch', '-q', 'main')

        git = described_class.new(repo_root: dir)

        expect(git.in_history?(side_sha, 'main')).to be(false)
      end
    end
  end
end
