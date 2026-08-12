# frozen_string_literal: true

require 'json'

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

    context 'with uncommitted changes in the worktree' do
      it 'ignores uncommitted changes by default' do
        GitSandbox.create do |dir|
          GitSandbox.write(dir, 'a.rb', '1')
          base_sha = GitSandbox.commit(dir, 'init')
          GitSandbox.write(dir, 'a.rb', '2')

          git = described_class.new(repo_root: dir)

          expect(git.changed_files(base_sha)).to eq([])
        end
      end

      it 'ignores uncommitted changes when explicitly given false' do
        GitSandbox.create do |dir|
          GitSandbox.write(dir, 'a.rb', '1')
          base_sha = GitSandbox.commit(dir, 'init')
          GitSandbox.write(dir, 'a.rb', '2')

          git = described_class.new(repo_root: dir)

          expect(git.changed_files(base_sha, include_uncommitted: false)).to eq([])
        end
      end

      it 'reports an unstaged worktree edit with status M' do
        GitSandbox.create do |dir|
          GitSandbox.write(dir, 'a.rb', '1')
          base_sha = GitSandbox.commit(dir, 'init')
          GitSandbox.write(dir, 'a.rb', '2')

          git = described_class.new(repo_root: dir)

          expect(git.changed_files(base_sha, include_uncommitted: true)).to eq([{ status: 'M', path: 'a.rb' }])
        end
      end

      it 'reports a staged (not committed) edit with status M' do
        GitSandbox.create do |dir|
          GitSandbox.write(dir, 'a.rb', '1')
          base_sha = GitSandbox.commit(dir, 'init')
          GitSandbox.write(dir, 'a.rb', '2')
          GitSandbox.run(dir, 'add', 'a.rb')

          git = described_class.new(repo_root: dir)

          expect(git.changed_files(base_sha, include_uncommitted: true)).to eq([{ status: 'M', path: 'a.rb' }])
        end
      end

      it 'reports a new untracked file with status A' do
        GitSandbox.create do |dir|
          GitSandbox.write(dir, 'a.rb', '1')
          base_sha = GitSandbox.commit(dir, 'init')
          GitSandbox.write(dir, 'b.rb', '1')

          git = described_class.new(repo_root: dir)

          expect(git.changed_files(base_sha, include_uncommitted: true)).to eq([{ status: 'A', path: 'b.rb' }])
        end
      end

      it 'does not report a gitignored untracked file' do
        GitSandbox.create do |dir|
          GitSandbox.write(dir, '.gitignore', "ignored.rb\n")
          GitSandbox.write(dir, 'a.rb', '1')
          base_sha = GitSandbox.commit(dir, 'init')
          GitSandbox.write(dir, 'ignored.rb', '1')

          git = described_class.new(repo_root: dir)

          expect(git.changed_files(base_sha, include_uncommitted: true)).to eq([])
        end
      end

      it 'reports a worktree deletion (not staged or committed) with status D' do
        GitSandbox.create do |dir|
          GitSandbox.write(dir, 'a.rb', '1')
          base_sha = GitSandbox.commit(dir, 'init')
          FileUtils.rm(File.join(dir, 'a.rb'))

          git = described_class.new(repo_root: dir)

          expect(git.changed_files(base_sha, include_uncommitted: true)).to eq([{ status: 'D', path: 'a.rb' }])
        end
      end

      it 'reports a staged (not committed) rename with status R and both paths' do
        GitSandbox.create do |dir|
          GitSandbox.write(dir, 'a.rb', '1' * 50)
          base_sha = GitSandbox.commit(dir, 'init')
          GitSandbox.run(dir, 'mv', 'a.rb', 'b.rb')

          git = described_class.new(repo_root: dir)

          expect(git.changed_files(base_sha, include_uncommitted: true))
            .to eq([{ status: 'R', path: 'b.rb', old_path: 'a.rb' }])
        end
      end

      it 'combines committed diff and uncommitted diff' do
        GitSandbox.create do |dir|
          GitSandbox.write(dir, 'a.rb', '1')
          GitSandbox.write(dir, 'b.rb', '1')
          base_sha = GitSandbox.commit(dir, 'init')
          GitSandbox.write(dir, 'a.rb', '2')
          GitSandbox.commit(dir, 'modify a')
          GitSandbox.write(dir, 'b.rb', '2')

          git = described_class.new(repo_root: dir)

          changes = git.changed_files(base_sha, include_uncommitted: true)

          expect(changes).to contain_exactly({ status: 'M', path: 'a.rb' }, { status: 'M', path: 'b.rb' })
        end
      end
    end
  end

  describe '#head_sha' do
    around do |example|
      original = ENV.fetch('GITHUB_EVENT_PATH', nil)
      example.run
    ensure
      original.nil? ? ENV.delete('GITHUB_EVENT_PATH') : ENV['GITHUB_EVENT_PATH'] = original
    end

    it 'returns the HEAD sha when GITHUB_EVENT_PATH is unset' do
      ENV.delete('GITHUB_EVENT_PATH')

      GitSandbox.create do |dir|
        GitSandbox.write(dir, 'a.rb', '1')
        head = GitSandbox.commit(dir, 'init')

        git = described_class.new(repo_root: dir)

        expect(git.head_sha).to eq(head)
      end
    end

    it 'returns the pull_request head sha instead of the synthetic merge commit' do
      GitSandbox.create do |dir|
        GitSandbox.write(dir, 'a.rb', '1')
        GitSandbox.commit(dir, 'init')
        GitSandbox.run(dir, 'switch', '-q', '-c', 'feature')
        GitSandbox.write(dir, 'b.rb', '1')
        head = GitSandbox.commit(dir, 'feature work')
        GitSandbox.run(dir, 'switch', '-q', 'main')
        GitSandbox.run(dir, 'merge', '-q', '--no-ff', 'feature', '-m', 'Merge PR')
        GitSandbox.run(dir, 'checkout', '-q', '--detach', 'HEAD')
        GitSandbox.write(dir, 'event.json', JSON.dump(pull_request: { head: { sha: head } }))
        ENV['GITHUB_EVENT_PATH'] = File.join(dir, 'event.json')

        git = described_class.new(repo_root: dir)

        expect(git.head_sha).to eq(head)
      end
    end

    it 'falls back to HEAD for a push event payload' do
      GitSandbox.create do |dir|
        GitSandbox.write(dir, 'a.rb', '1')
        head = GitSandbox.commit(dir, 'init')
        GitSandbox.write(dir, 'event.json', JSON.dump(ref: 'refs/heads/main', after: head))
        ENV['GITHUB_EVENT_PATH'] = File.join(dir, 'event.json')

        git = described_class.new(repo_root: dir)

        expect(git.head_sha).to eq(head)
      end
    end

    it 'falls back to HEAD when GITHUB_EVENT_PATH points to a missing file' do
      GitSandbox.create do |dir|
        GitSandbox.write(dir, 'a.rb', '1')
        head = GitSandbox.commit(dir, 'init')
        ENV['GITHUB_EVENT_PATH'] = File.join(dir, 'does-not-exist.json')

        git = described_class.new(repo_root: dir)

        expect(git.head_sha).to eq(head)
      end
    end

    it 'falls back to HEAD when the event payload is malformed JSON' do
      GitSandbox.create do |dir|
        GitSandbox.write(dir, 'a.rb', '1')
        head = GitSandbox.commit(dir, 'init')
        GitSandbox.write(dir, 'event.json', '{not json')
        ENV['GITHUB_EVENT_PATH'] = File.join(dir, 'event.json')

        git = described_class.new(repo_root: dir)

        expect(git.head_sha).to eq(head)
      end
    end

    it 'falls back to HEAD when pull_request is a string' do
      GitSandbox.create do |dir|
        GitSandbox.write(dir, 'a.rb', '1')
        head = GitSandbox.commit(dir, 'init')
        GitSandbox.write(dir, 'event.json', JSON.dump(pull_request: 'oops'))
        ENV['GITHUB_EVENT_PATH'] = File.join(dir, 'event.json')

        git = described_class.new(repo_root: dir)

        expect(git.head_sha).to eq(head)
      end
    end

    it 'falls back to HEAD when the payload top level is an array' do
      GitSandbox.create do |dir|
        GitSandbox.write(dir, 'a.rb', '1')
        head = GitSandbox.commit(dir, 'init')
        GitSandbox.write(dir, 'event.json', JSON.dump(['pull_request']))
        ENV['GITHUB_EVENT_PATH'] = File.join(dir, 'event.json')

        git = described_class.new(repo_root: dir)

        expect(git.head_sha).to eq(head)
      end
    end

    it 'falls back to HEAD when sha is an empty string' do
      GitSandbox.create do |dir|
        GitSandbox.write(dir, 'a.rb', '1')
        head = GitSandbox.commit(dir, 'init')
        GitSandbox.write(dir, 'event.json', JSON.dump(pull_request: { head: { sha: '' } }))
        ENV['GITHUB_EVENT_PATH'] = File.join(dir, 'event.json')

        git = described_class.new(repo_root: dir)

        expect(git.head_sha).to eq(head)
      end
    end

    it 'falls back to HEAD when sha is a number' do
      GitSandbox.create do |dir|
        GitSandbox.write(dir, 'a.rb', '1')
        head = GitSandbox.commit(dir, 'init')
        GitSandbox.write(dir, 'event.json', JSON.dump(pull_request: { head: { sha: 12_345 } }))
        ENV['GITHUB_EVENT_PATH'] = File.join(dir, 'event.json')

        git = described_class.new(repo_root: dir)

        expect(git.head_sha).to eq(head)
      end
    end

    it 'falls back to HEAD when GITHUB_EVENT_PATH is an empty string' do
      GitSandbox.create do |dir|
        GitSandbox.write(dir, 'a.rb', '1')
        head = GitSandbox.commit(dir, 'init')
        ENV['GITHUB_EVENT_PATH'] = ''

        git = described_class.new(repo_root: dir)

        expect(git.head_sha).to eq(head)
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
