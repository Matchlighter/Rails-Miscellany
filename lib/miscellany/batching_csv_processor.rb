require 'csv'

module Miscellany
  class BatchingCsvProcessor
    attr_accessor :csv, :file_name

    class RowError < StandardError; end

    def initialize(csv, file_name: nil)
      @csv = csv
      @file_name = file_name
    end

    def process_in_batches(&blk)
      batch = BatchProcessor.new(&blk)
      CSV.new(csv, headers: true, header_converters: :symbol).each.with_index do |row, line|
        row[:line_number] = line + 1
        next unless validate_line(row)

        batch << row
      end
      batch.flush
    end

    def get_row_errors(row); end

    def find_or_init(_row)
      raise NotImplementedError
    end

    def apply_row_to_model(_row, _instance)
      raise NotImplementedError
    end

    def log_line_error(message, line_number, **kwargs)
      raise NotImplementedError
    end

    def validate_line(row)
      errors = get_row_errors(row) || []
      if errors.present?
        log_line_error(errors[0], row[:line_number])
        false
      else
        true
      end
    end

    def batch_rows_to_models(rows)
      rows.map { |row| build_model_from_row(row) }.reject { |inst| inst.nil? || !inst.changed? }
    end

    def build_model_from_row(row)
      model = find_or_init(row)
      apply_row_to_model(row, model)
      return nil if model.respond_to?(:discarded_at) && model.discarded_at.present? && !model.persisted?

      model
    rescue ActiveRecord::RecordNotFound, RowError => err
      log_line_error(err.message, row[:line_number], exception: err)
      nil
    rescue StandardError => err
      log_line_error('An Internal Error Occurred', row[:line_number], exception: err)
      Raven.capture_exception(err) if defined?(Raven)
      nil
    end

    def map_defined_columns(row, map)
      newh = {}
      map.each do |newk, oldk|
        next unless row.include?(oldk)

        newh[newk] = row[oldk]
      end
      newh
    end

    def self.file_matches?(file)
      header = file.readline.strip.split(',')
      file.try(:rewind)
      headers_match?(header)
    end

    def self.headers_match?(headers)
      (self::HEADERS - headers).empty?
    end
  end
end
