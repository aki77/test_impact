# frozen_string_literal: true

require 'spec_helper'
require 'renderer'

RSpec.describe Renderer do
  it 'renders the greeting template' do
    expect(described_class.new.render_greeting('world')).to eq("<p>Hello, world!</p>\n")
  end
end
