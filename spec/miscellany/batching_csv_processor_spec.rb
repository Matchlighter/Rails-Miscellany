require 'spec_helper'

RSpec.describe Miscellany::BatchingCsvProcessor do
  with_model :Widget do
    table do |t|
      t.string :name
      t.string :size
    end
  end

  # Concrete processor wiring the abstract hooks to a real model.
  let(:processor_class) do
    klass = Class.new(described_class) do
      attr_reader :logged_errors

      def initialize(*)
        super
        @logged_errors = []
      end

      def get_row_errors(row)
        row[:name].blank? ? ['name is required'] : []
      end

      def log_line_error(message, line_number, **_kwargs)
        @logged_errors << [line_number, message]
      end

      def find_or_init(row)
        Widget.find_or_initialize_by(name: row[:name])
      end

      def apply_row_to_model(row, instance)
        raise Miscellany::BatchingCsvProcessor::RowError, 'bad size' if row[:size] == 'bad'

        instance.size = row[:size]
      end
    end
    klass.const_set(:HEADERS, %i[name size])
    klass
  end

  let(:csv) { "name,size\nwidget_a,small\nwidget_b,large\n" }

  def processor(data = csv)
    processor_class.new(data)
  end

  describe '#process_in_batches' do
    it 'yields the validated rows, tagged with line numbers' do
      seen = []
      processor.process_in_batches { |batch| seen.concat(batch) }

      expect(seen.map { |r| r[:name] }).to eq %w[widget_a widget_b]
      expect(seen.map { |r| r[:line_number] }).to eq [1, 2]
    end

    it 'skips invalid rows and logs an error for each' do
      proc = processor("name,size\n,small\nwidget_b,large\n")
      seen = []
      proc.process_in_batches { |batch| seen.concat(batch) }

      expect(seen.map { |r| r[:name] }).to eq %w[widget_b]
      expect(proc.logged_errors).to eq [[1, 'name is required']]
    end
  end

  describe '#build_model_from_row' do
    it 'returns a populated, changed model for a valid row' do
      model = processor.build_model_from_row(name: 'widget_a', size: 'small', line_number: 1)
      expect(model).to be_a(Widget)
      expect(model.size).to eq 'small'
      expect(model).to be_changed
    end

    it 'logs and swallows a RowError, returning nil' do
      proc = processor
      result = proc.build_model_from_row(name: 'widget_a', size: 'bad', line_number: 4)
      expect(result).to be_nil
      expect(proc.logged_errors).to eq [[4, 'bad size']]
    end
  end

  describe '#batch_rows_to_models' do
    it 'returns the changed models built from the rows' do
      rows = [
        { name: 'widget_a', size: 'small', line_number: 1 },
        { name: 'widget_b', size: 'large', line_number: 2 },
      ]
      models = processor.batch_rows_to_models(rows)
      expect(models.map(&:name)).to eq %w[widget_a widget_b]
    end
  end

  describe '#map_defined_columns' do
    it 'remaps only the keys present in the row' do
      row = { old_name: 'a', old_size: 'b' }
      mapped = processor.map_defined_columns(row, name: :old_name, size: :old_size, missing: :nope)
      expect(mapped).to eq(name: 'a', size: 'b')
    end
  end

  describe '.headers_match?' do
    it 'is true when every required header is present' do
      expect(processor_class.headers_match?(%i[name size extra])).to be true
    end

    it 'is false when a required header is missing' do
      expect(processor_class.headers_match?(%i[name])).to be false
    end
  end

  describe '.file_matches?' do
    # file_matches? parses the raw header line into strings, so a class using
    # string HEADERS is what the method is designed to compare against.
    let(:string_header_class) do
      klass = Class.new(described_class)
      klass.const_set(:HEADERS, %w[name size])
      klass
    end

    it 'is true when the header line contains the required columns' do
      file = StringIO.new("name,size\nwidget_a,small\n")
      expect(string_header_class.file_matches?(file)).to be true
    end

    it 'is false when a required column is missing' do
      file = StringIO.new("name\nwidget_a\n")
      expect(string_header_class.file_matches?(file)).to be false
    end

    it 'rewinds the file so it can be read again afterward' do
      file = StringIO.new("name,size\nwidget_a,small\n")
      string_header_class.file_matches?(file)
      expect(file.readline).to eq "name,size\n"
    end
  end
end
