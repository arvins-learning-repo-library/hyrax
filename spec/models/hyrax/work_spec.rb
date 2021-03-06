# frozen_string_literal: true

require 'spec_helper'
require 'hyrax/specs/shared_specs/hydra_works'

RSpec.describe Hyrax::Work do
  subject(:work) { described_class.new }

  it_behaves_like 'a Hyrax::Work'

  describe '#human_readable_type' do
    it 'has a human readable type' do
      expect(work.human_readable_type).to eq 'Work'
    end
  end
end
