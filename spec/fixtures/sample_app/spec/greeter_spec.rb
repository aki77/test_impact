# frozen_string_literal: true

require 'spec_helper'
require 'greeter'

RSpec.describe Greeter do
  it 'greets by name' do
    expect(described_class.new.greet('world')).to eq('Hello, world!')
  end
end
