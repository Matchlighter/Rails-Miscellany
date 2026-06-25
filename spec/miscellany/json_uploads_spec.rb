require 'spec_helper'

# The process_action override needs a full controller/request stack to exercise.
# The recursive parameter-merge logic, which is the substantive part, is unit
# tested here in isolation.
RSpec.describe Miscellany::JsonUploads do
  let(:instance) { Class.new { include Miscellany::JsonUploads }.new }

  # _merge_json_params logs a warning (via Rails.logger) when a value is supplied
  # in both layers; stub Rails since the gem loads without it in the suite.
  before { stub_const('Rails', double('Rails', logger: Logger.new(IO::NULL))) }

  def merge(base, layer)
    instance.send(:_merge_json_params, base, layer)
  end

  describe 'scalars' do
    it 'prefers the layer value over the base' do
      expect(merge('base', 'layer')).to eq 'layer'
    end

    it 'falls back to the base when the layer is blank' do
      expect(merge('base', nil)).to eq 'base'
      expect(merge('base', '')).to eq 'base'
    end
  end

  describe 'hashes' do
    it 'deep-merges, with the layer winning on overlapping leaves' do
      expect(merge({ 'a' => 1, 'b' => 2 }, { 'b' => 3 })).to eq('a' => 1, 'b' => 3)
    end

    it 'keeps base-only keys when the layer omits them' do
      expect(merge({ 'a' => 1 }, {})).to eq('a' => 1)
    end

    it 'merges nested hashes recursively' do
      base = { 'outer' => { 'x' => 1, 'y' => 2 } }
      layer = { 'outer' => { 'y' => 9 } }
      expect(merge(base, layer)).to eq('outer' => { 'x' => 1, 'y' => 9 })
    end
  end

  describe 'arrays' do
    it 'merges element-wise against a parallel array layer' do
      expect(merge([{ 'x' => 1 }, { 'x' => 2 }], [{ 'x' => 9 }, {}]))
        .to eq([{ 'x' => 9 }, { 'x' => 2 }])
    end

    it 'merges element-wise against an index-keyed hash layer' do
      expect(merge([10, 20], { '0' => 99 })).to eq([99, 20])
    end
  end
end
