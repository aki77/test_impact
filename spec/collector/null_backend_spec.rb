# frozen_string_literal: true

require 'test_impact/collector/null_backend'

RSpec.describe TestImpact::Collector::NullBackend do
  subject(:backend) { described_class.new }

  it 'has a name of null' do
    expect(backend.name).to eq('null')
  end

  it 'starts without error' do
    expect { backend.start }.not_to raise_error
  end

  it 'returns an empty hash from stop' do
    expect(backend.stop).to eq({})
  end
end
