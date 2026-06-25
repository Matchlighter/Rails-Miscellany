require 'spec_helper'

RSpec.describe Miscellany::BatchProcessor do
  it 'processes a batch as soon as it reaches the batch size' do
    batches = []
    processor = described_class.new(of: 2) { |batch| batches << batch.dup }

    processor << 1
    expect(batches).to be_empty # not yet full

    processor << 2
    expect(batches).to eq [[1, 2]] # flushed at size 2

    processor << 3
    expect(batches).to eq [[1, 2]] # partial batch held back
  end

  describe '#flush' do
    it 'processes the remaining partial batch' do
      batches = []
      processor = described_class.new(of: 5) { |batch| batches << batch.dup }

      processor << 1
      processor << 2
      processor.flush

      expect(batches).to eq [[1, 2]]
    end

    it 'does nothing when there is nothing buffered' do
      calls = 0
      processor = described_class.new(of: 5) { |_batch| calls += 1 }
      processor.flush
      expect(calls).to eq 0
    end

    it 'does not re-run on a second flush' do
      batches = []
      processor = described_class.new(of: 5) { |batch| batches << batch.dup }
      processor << 1
      processor.flush
      processor.flush
      expect(batches).to eq [[1]]
    end
  end

  describe '#add_all' do
    it 'enqueues each item, flushing full batches along the way' do
      batches = []
      processor = described_class.new(of: 2) { |batch| batches << batch.dup }
      processor.add_all([1, 2, 3, 4, 5])
      expect(batches).to eq [[1, 2], [3, 4]]
      processor.flush
      expect(batches).to eq [[1, 2], [3, 4], [5]]
    end
  end

  describe 'ensure_once' do
    it 'invokes the block once on flush even with no items' do
      batches = []
      processor = described_class.new(of: 5, ensure_once: true) { |batch| batches << batch.dup }
      processor.flush
      expect(batches).to eq [[]]
    end

    it 'does not invoke the block an extra time when items were already processed' do
      batches = []
      processor = described_class.new(of: 2, ensure_once: true) { |batch| batches << batch.dup }
      processor << 1
      processor << 2 # full batch flushes here
      processor.flush # nothing buffered, already flushed once
      expect(batches).to eq [[1, 2]]
    end
  end
end
