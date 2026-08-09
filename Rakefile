# frozen_string_literal: true

require 'bundler/gem_tasks'
require 'rspec/core/rake_task'

RSpec::Core::RakeTask.new(:spec) do |t|
  t.pattern = 'spec/**/*_spec.rb'
  t.exclude_pattern = 'spec/{integration,fixtures}/**/*_spec.rb'
end

RSpec::Core::RakeTask.new('spec:integration') do |t|
  t.pattern = 'spec/integration/**/*_spec.rb'
  # Override .rspec's --exclude-pattern (which excludes spec/integration for
  # bare `rspec` runs); CLI options take precedence over the .rspec file.
  t.exclude_pattern = 'spec/fixtures/**/*_spec.rb'
  t.rspec_opts = '--tag ddcov'
end

task default: :spec
