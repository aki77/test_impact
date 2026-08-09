# frozen_string_literal: true

require 'tmpdir'
require 'open3'
require 'fileutils'

module GitSandbox
  # Creates a real git repository in a temp dir and yields its absolute path.
  # Commands run with -C <dir>, independent of the current process cwd.
  def self.create
    Dir.mktmpdir do |dir|
      run(dir, 'init', '-q', '-b', 'main')
      run(dir, 'config', 'user.email', 'test@example.com')
      run(dir, 'config', 'user.name', 'Test')
      run(dir, 'config', 'core.hooksPath', '/dev/null')
      yield dir
    end
  end

  def self.run(dir, *args)
    stdout, status = Open3.capture2('git', '-C', dir, '-c', 'core.hooksPath=/dev/null', *args)
    raise "git #{args.join(' ')} failed in #{dir}" unless status.success?

    stdout
  end

  def self.write(dir, relative_path, content)
    full_path = File.join(dir, relative_path)
    FileUtils.mkdir_p(File.dirname(full_path))
    File.write(full_path, content)
  end

  def self.commit(dir, message)
    run(dir, 'add', '-A')
    run(dir, 'commit', '-q', '-m', message)
    run(dir, 'rev-parse', 'HEAD').strip
  end
end
