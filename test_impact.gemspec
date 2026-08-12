# frozen_string_literal: true

require_relative 'lib/test_impact/version'

Gem::Specification.new do |spec|
  spec.name = 'test_impact'
  spec.version = TestImpact::VERSION
  spec.authors = ['aki77']

  spec.summary = 'Test Impact Analysis for Ruby without Datadog backend'
  spec.description = "Collects per-test coverage via datadog-ci's native extension " \
                     'and selects impacted specs from git diff.'
  spec.homepage = 'https://github.com/aki77/test_impact_analysis'
  spec.license = 'MIT'
  spec.required_ruby_version = '>= 3.3'

  spec.metadata['homepage_uri'] = spec.homepage
  spec.metadata['source_code_uri'] = spec.homepage
  spec.metadata['rubygems_mfa_required'] = 'true'

  spec.files =
    Dir.chdir(__dir__) do
      # The `-ja` skill variants are for repo contributors only; the gem ships the English ones.
      `git ls-files -z -- lib exe skills README.md LICENSE.txt test_impact.gemspec`
        .split("\x0")
        .grep_v(%r{\Askills/.*-ja\.md\z})
    end
  spec.bindir = 'exe'
  spec.executables = ['test-impact']
  spec.require_paths = ['lib']

  spec.add_dependency 'datadog-ci', '>= 1.20', '< 2.0'
  spec.add_dependency 'thor', '~> 1.3'
end
