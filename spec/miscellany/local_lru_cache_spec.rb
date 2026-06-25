require 'spec_helper'

RSpec.describe Miscellany::LocalLruCache do
  subject(:cache) { described_class.new(3) }

  describe '#[]= and #[]' do
    it 'stores and retrieves values' do
      cache[:a] = 1
      expect(cache[:a]).to eq 1
    end

    it 'returns nil for missing keys' do
      expect(cache[:missing]).to be_nil
    end

    it 'returns the assigned value from []=' do
      expect(cache.send(:[]=, :a, 42)).to eq 42
    end

    it 'evicts the least-recently-used entry once over capacity' do
      cache[:a] = 1
      cache[:b] = 2
      cache[:c] = 3
      cache[:d] = 4 # pushes out :a, the oldest

      expect(cache[:a]).to be_nil
      expect(cache[:b]).to eq 2
      expect(cache[:d]).to eq 4
      expect(cache.count).to eq 3
    end

    it 'treats a read as a use, protecting the entry from eviction' do
      cache[:a] = 1
      cache[:b] = 2
      cache[:c] = 3
      cache[:a] # touch :a so :b becomes least-recently-used
      cache[:d] = 4

      expect(cache[:a]).to eq 1
      expect(cache[:b]).to be_nil
    end

    it 'treats re-assignment as a use' do
      cache[:a] = 1
      cache[:b] = 2
      cache[:c] = 3
      cache[:a] = 10 # refresh recency of :a
      cache[:d] = 4

      expect(cache[:a]).to eq 10
      expect(cache[:b]).to be_nil
    end
  end

  describe '#fetch' do
    it 'yields and stores on a miss' do
      calls = 0
      result = cache.fetch(:a) { calls += 1; 'computed' }
      expect(result).to eq 'computed'
      expect(calls).to eq 1
    end

    it 'does not yield on a hit' do
      cache[:a] = 'stored'
      calls = 0
      result = cache.fetch(:a) { calls += 1; 'computed' }
      expect(result).to eq 'stored'
      expect(calls).to eq 0
    end
  end

  describe '#delete' do
    it 'removes an entry' do
      cache[:a] = 1
      expect(cache.delete(:a)).to eq 1
      expect(cache[:a]).to be_nil
    end
  end

  describe '#clear' do
    it 'empties the cache' do
      cache[:a] = 1
      cache[:b] = 2
      cache.clear
      expect(cache.count).to eq 0
    end
  end

  describe '#to_a and #each' do
    it 'orders entries most-recently-used first' do
      cache[:a] = 1
      cache[:b] = 2
      expect(cache.to_a).to eq [[:b, 2], [:a, 1]]
    end

    it 'iterates most-recently-used first' do
      cache[:a] = 1
      cache[:b] = 2
      seen = []
      cache.each { |pair| seen << pair }
      expect(seen).to eq [[:b, 2], [:a, 1]]
    end
  end

  describe '#max_size=' do
    it 'rejects a size below one' do
      expect { cache.max_size = 0 }.to raise_error(ArgumentError)
    end

    it 'evicts down to the new size, dropping the oldest entries' do
      cache[:a] = 1
      cache[:b] = 2
      cache[:c] = 3
      cache.max_size = 1

      expect(cache.count).to eq 1
      expect(cache[:c]).to eq 3 # newest survives
      expect(cache[:a]).to be_nil
    end

    it 'keeps every entry when only shrinking by one' do
      cache[:a] = 1
      cache[:b] = 2
      cache[:c] = 3
      cache.max_size = 2

      expect(cache.count).to eq 2
      expect(cache[:b]).to eq 2
      expect(cache[:c]).to eq 3
    end
  end
end
