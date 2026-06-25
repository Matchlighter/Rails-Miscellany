require 'spec_helper'

RSpec.describe Miscellany::BatchMatcher do
  describe 'simple (single-model) matching' do
    with_model :Rule do
      table do |t|
        t.string :import_id
        t.string :label
      end
    end

    let!(:rule_a) { Rule.create!(import_id: 'IMP-A', label: 'Alpha') }
    let!(:rule_b) { Rule.create!(import_id: 'IMP-B', label: 'Beta') }

    # [csv_key, db_key, human_name]; first entry is the primary column.
    let(:columns) { [[:rule_id, :id, 'ID'], [:rule_import_id, :import_id, 'Import ID']] }
    let(:rows) do
      [
        { rule_id: rule_a.id, rule_import_id: 'IMP-A' },
        { rule_id: rule_b.id, rule_import_id: 'IMP-B' },
      ]
    end

    def matcher(opts = {})
      described_class.new(Rule, rows, **{ columns: columns }.merge(opts))
    end

    describe '#get_for_row!' do
      it 'matches on the primary column' do
        expect(matcher.get_for_row!(rule_id: rule_a.id)).to eq rule_a
      end

      it 'matches on a secondary column' do
        expect(matcher.get_for_row!(rule_import_id: 'IMP-B')).to eq rule_b
      end

      it 'matches when consistent values are given for multiple columns' do
        expect(matcher.get_for_row!(rule_id: rule_a.id, rule_import_id: 'IMP-A')).to eq rule_a
      end

      it 'raises RecordNotFound when nothing matches' do
        expect { matcher.get_for_row!(rule_import_id: 'NOPE') }
          .to raise_error(ActiveRecord::RecordNotFound, /Import ID/)
      end
    end

    describe '#get_for_row' do
      it 'returns nil instead of raising when nothing matches' do
        expect(matcher.get_for_row(rule_import_id: 'NOPE')).to be_nil
      end

      it 'returns the record when it matches' do
        expect(matcher.get_for_row(rule_id: rule_b.id)).to eq rule_b
      end
    end

    describe '#get_primary_for_row!' do
      it 'returns the primary key value for a primary-column row' do
        expect(matcher.get_primary_for_row!(rule_id: rule_a.id)).to eq rule_a.id.to_s
      end

      it 'resolves the primary key value from a secondary column' do
        expect(matcher.get_primary_for_row!(rule_import_id: 'IMP-B')).to eq rule_b.id.to_s
      end
    end

    describe '#should_match?' do
      it 'is true when any configured column has a value' do
        expect(matcher.should_match?(rule_import_id: 'IMP-A')).to be true
      end

      it 'is false when no configured column has a value' do
        expect(matcher.should_match?(unrelated: 'x')).to be false
        expect(matcher.should_match?({})).to be false
      end
    end

    describe 'validate_all' do
      let(:conflicting_row) { { rule_id: rule_a.id, rule_import_id: 'IMP-B' } }

      it 'raises when columns resolve to different records (default)' do
        expect { matcher.get_for_row!(conflicting_row) }
          .to raise_error(ActiveRecord::RecordNotFound, /resolved to different objects/)
      end

      it 'returns the first match when validation is disabled' do
        expect(matcher(validate_all: false).get_for_row!(conflicting_row)).to eq rule_a
      end
    end
  end

  describe 'polymorphic matching' do
    with_model :Account do
      table { |t| t.integer :canvas_id }
    end

    with_model :Course do
      table { |t| t.integer :canvas_id }
    end

    let!(:account) { Account.create!(canvas_id: 100) }
    let!(:course) { Course.create!(canvas_id: 200) }

    let(:columns) { [[:canvas_context_id, :canvas_id, 'Canvas ID']] }
    let(:rows) do
      [
        { context_type: 'Account', canvas_context_id: 100 },
        { context_type: 'Course', canvas_context_id: 200 },
      ]
    end

    def matcher
      described_class.new(
        [Account, Course], rows,
        polymorphic_on: :context_type,
        columns: columns,
      )
    end

    it 'resolves rows to the correct model based on the polymorphic type' do
      expect(matcher.get_for_row!(rows[0])).to eq account
      expect(matcher.get_for_row!(rows[1])).to eq course
    end

    it 'raises for an unknown polymorphic type' do
      expect { matcher.get_for_row!(context_type: 'Widget', canvas_context_id: 1) }
        .to raise_error(ActiveRecord::RecordNotFound)
    end
  end
end
