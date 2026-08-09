# frozen_string_literal: true

require 'spec_helper'
require 'calculator'

RSpec.describe Calculator do
  it 'adds two numbers' do
    expect(described_class.new.add(1, 2)).to eq(3)
  end
end
