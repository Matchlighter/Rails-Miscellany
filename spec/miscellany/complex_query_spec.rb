require 'spec_helper'

# Concrete subclass exercising the abstract ComplexQuery template. A named
# (non-anonymous) class is required: #in_batches derives a temp-table name from
# self.class.name, and #valid_sorts reads self.class::SORTABLE_COLUMNS.
class WidgetReportQuery < Miscellany::ComplexQuery
  SORTABLE_COLUMNS = { 'name' => 'name' }.freeze

  def build_query
    "SELECT id, name FROM #{options[:table]}"
  end

  def build_count_query
    "SELECT COUNT(*) AS count FROM #{options[:table]}"
  end
end

RSpec.describe Miscellany::ComplexQuery do
  with_model :Widget do
    table { |t| t.string :name }
  end

  let(:table) { Widget.table_name }

  before do
    %w[apple banana cherry].each { |n| Widget.create!(name: n) }
  end

  def query(opts = {})
    WidgetReportQuery.new({ table: table }.merge(opts))
  end

  describe '#count' do
    it 'returns the scalar count from build_count_query' do
      expect(query.count).to eq 3
    end
  end

  describe '#page' do
    it 'returns a page of records with pagination metadata' do
      result = query(sort: 'name').page(1, page_size: 2)

      expect(result[:page]).to eq 1
      expect(result[:total_count]).to eq 3
      expect(result[:page_count]).to eq 2 # ceil(3 / 2)
      expect(result[:page_size]).to eq 2
      expect(result[:records].map { |r| r['name'] }).to eq %w[apple banana]
    end

    it 'returns the second page' do
      result = query(sort: 'name').page(2, page_size: 2)
      expect(result[:records].map { |r| r['name'] }).to eq %w[cherry]
    end

    it 'clamps a page below one up to one' do
      expect(query.page(0, page_size: 2)[:page]).to eq 1
    end

    it 'floors a page size below two to ten' do
      expect(query.page(1, page_size: 1)[:page_size]).to eq 10
    end

    it 'reports the sort string when sorting' do
      expect(query(sort: 'name').page(1)[:sort]).to include('name')
    end
  end

  describe '#slice' do
    it 'returns records at the given offset and length, honoring raw_sort' do
      records = query.slice(1, 1, raw_sort: 'name ASC')
      expect(records.map { |r| r[:name] }).to eq %w[banana]
    end

    it 'exposes records with indifferent access' do
      record = query.slice(0, 1, raw_sort: 'name ASC').first
      expect(record[:name]).to eq 'apple'
      expect(record['name']).to eq 'apple'
    end
  end

  describe '#sql' do
    it 'appends ORDER BY when a sort is configured' do
      expect(query(sort: 'name').sql).to match(/ORDER BY/i)
    end

    it 'omits ORDER BY when no sort is configured' do
      expect(query.sql).not_to match(/ORDER BY/i)
    end
  end

  describe '#in_batches' do
    it 'yields every record across batches and cleans up the temp table' do
      seen = []
      query.in_batches(of: 2) { |batch| seen.concat(batch.map { |r| r[:name] }) }
      expect(seen.sort).to eq %w[apple banana cherry]
    end

    it 'can be run repeatedly (temp table is dropped each time)' do
      expect { 2.times { query.in_batches(of: 2) { |_b| } } }.not_to raise_error
    end
  end

  describe '#find_each' do
    it 'yields each record as a hash' do
      names = []
      query.find_each(batch_size: 2) { |r| names << r[:name] }
      expect(names.sort).to eq %w[apple banana cherry]
    end
  end

  describe '#valid_sort?' do
    it 'returns false for a blank sort' do
      expect(query.valid_sort?(nil)).to be false
      expect(query.valid_sort?('')).to be false
    end

    it 'returns true for a sort over a sortable column' do
      expect(query.valid_sort?('name')).to be true
    end

    it 'returns false for a sort over an unknown column' do
      expect(query.valid_sort?('not_a_column')).to be false
    end
  end

  describe '#join_filters (protected helper)' do
    subject(:q) { query }

    it 'ANDs present clauses together, wrapping each in parentheses' do
      expect(q.send(:join_filters, 'a = 1', 'b = 2')).to eq '(a = 1) AND (b = 2)'
    end

    it 'drops blank clauses' do
      expect(q.send(:join_filters, 'a = 1', nil, '', false)).to eq '(a = 1)'
    end

    it 'falls back to 1=1 when nothing is present' do
      expect(q.send(:join_filters, nil, false)).to eq '1=1'
    end
  end

  describe '#datetime_filter (protected helper)' do
    subject(:q) { query }

    it 'builds a BETWEEN clause when both bounds are present' do
      sql = q.send(:datetime_filter, 'created_at', ['2024-01-01', '2024-01-31'])
      expect(sql).to match(/created_at BETWEEN '2024-01-01.*' AND '2024-01-31/)
    end

    it 'builds a lower-bound clause when only the start is present' do
      sql = q.send(:datetime_filter, 'created_at', ['2024-01-01', nil])
      expect(sql).to match(/created_at >= '2024-01-01/)
    end

    it 'builds an upper-bound clause when only the end is present' do
      sql = q.send(:datetime_filter, 'created_at', [nil, '2024-01-31'])
      expect(sql).to match(/created_at <= '2024-01-31/)
    end
  end
end
