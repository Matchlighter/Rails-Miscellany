require 'spec_helper'

RSpec.describe Miscellany::BatchedDestruction do
  with_model :Widget do
    table do |t|
      t.string :name
      t.boolean :archived, default: false
    end

    model do
      include Miscellany::BatchedDestruction
    end
  end

  before do
    5.times { |i| Widget.create!(name: "w#{i}") }
  end

  describe '.bulk_destroy' do
    it 'deletes every matching record' do
      expect { Widget.bulk_destroy }.to change(Widget, :count).from(5).to(0)
    end

    it 'works against a scoped relation, deleting only the scope' do
      Widget.where(name: 'w0').update_all(archived: true)
      expect { Widget.where(archived: true).bulk_destroy }
        .to change(Widget, :count).from(5).to(4)
    end

    it 'runs the bulk_destroy callbacks around the deletion' do
      ran = []
      Widget.set_callback(:bulk_destroy, :before) { ran << :before }
      Widget.set_callback(:bulk_destroy, :after) { ran << :after }

      Widget.bulk_destroy
      expect(ran).to eq [:before, :after]
    end

    it 'runs the per-batch callbacks' do
      seen_batches = 0
      Widget.set_callback(:destroy_batch, :before) { seen_batches += 1 }

      Widget.bulk_destroy
      expect(seen_batches).to be >= 1
    end
  end

  describe '.destroy_bulk_batch override (soft deletion)' do
    it 'lets a model swap hard deletion for a custom strategy' do
      def Widget.destroy_bulk_batch(batch, _options)
        where(id: batch.map(&:id)).update_all(archived: true)
      end

      expect { Widget.bulk_destroy }.not_to change(Widget, :count)
      expect(Widget.where(archived: false)).to be_empty
    end
  end

  describe '#destroy' do
    it 'routes a single record through the bulk path by default' do
      widget = Widget.first
      expect { widget.destroy }.to change(Widget, :count).from(5).to(4)
      expect(Widget.exists?(widget.id)).to be false
    end
  end
end
