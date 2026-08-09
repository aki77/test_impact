# frozen_string_literal: true

require 'stringio'

module CaptureOutput
  def capture_output
    original_stdout = $stdout
    original_stderr = $stderr
    $stdout = StringIO.new
    $stderr = StringIO.new
    yield
    [$stdout.string, $stderr.string]
  ensure
    $stdout = original_stdout
    $stderr = original_stderr
  end
end

RSpec.configure do |config|
  config.include CaptureOutput
end
