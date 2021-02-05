module Miscellany
  # Matches a set of rows (eg from a CSV) against Rows in the Database.
  #
  # Examples:
  #   rule_matcher = BatchMatcher.new(
  #     Rule, rows,
  #     validate_all: false,
  #     columns: [[:rule_id, :id, 'ID'], [:rule_import_id, :import_id, 'Import ID']]
  #   )
  #   context_matcher = BatchMatcher.new(
  #     [Account, Course], rows,
  #     polymorphic_on: :rule_context,
  #     columns: [[:canvas_context_id, :canvas_id, 'Canvas ID'], [:sis_context_id, :sis_id, 'SIS ID']]
  #   )
  #   role_matcher = BatchMatcher.new(
  #     Role, rows,
  #     columns: [[:canvas_role_id, :canvas_id, 'Canvas Role ID'], [:role_label, :label, 'Role Label']]
  #   )
  #
  # Params:
  # @param clazz - Model or ActiveRecord::Realtion
  # @param rows - Data to search the DB for matches
  # @param columns - [[CSV Header Key, Model Key, (Human Name)], ...]
  class BatchMatcher
    attr_reader :rows, :maps, :columns, :primary_column

    def initialize(clazz, rows, columns:, polymorphic_on: false, validate_all: true)
      # columns: [csv_key, db_key, human_name]
      @options = {
        mode: :eager,
        polymorphic_on: polymorphic_on,
        validate_all: validate_all
      }
      @clazz = clazz
      @columns = columns
      @primary_column = columns[0]
      @rows = rows
      @maps = {}
      @loaded_columns = {}
      @mode = :eager
    end

    def get_for_row!(row)
      resolve_row_value(row, :get_by_column)
    end

    def get_for_row(row)
      get_for_row!(row)
    rescue ActiveRecord::RecordNotFound
      nil
    end

    def get_primary_for_row!(row)
      resolve_row_value(row, :column_to_primary_key)
    end

    def get_primary_for_row(row)
      get_primary_for_row!(row)
    rescue ActiveRecord::RecordNotFound
      nil
    end

    # Returns True if the row has a value for any of this Matcher's Columns
    def should_match?(row)
      @columns.any? { |col| row[col[0]].present? }
    end

    protected

    def get_by_column(column, row)
      if column == @primary_column
        column_value(column, row)
      else
        mapped_id = column_value(column, row)
        get_column_map(primary_column, row, via_column: column)[transform_key(mapped_id)]
      end
    end

    def column_value(column, row)
      get_column_map(column, row)[transform_key(row[column[0]])]
    end

    def column_to_primary_key(column, row)
      if column == @primary_column
        transform_key(row[column[0]])
      else
        transform_key(column_value(column, row))
      end
    end

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity
    def resolve_row_value(row, resolver)
      found_values = []
      @columns.each do |c|
        next unless row[c[0]].present?

        inst = send(resolver, c, row)
        if inst.nil? && (!found_values.present? || @options[:validate_all])
          clazz = as_class(get_base_query(row))
          raise ActiveRecord::RecordNotFound, "could not find #{clazz.name} with #{c[2] || c[0]} #{row[c[0]]}"
        end
        found_values << inst
      end

      if @options[:validate_all] && found_values.uniq.count > 1
        raise ActiveRecord::RecordNotFound, "multiple of [#{@columns.pluck(2).join(', ')}] were supplied, but resolved to different objects" # rubocop:disable Metrics/LineLength
      end

      found_values[0]
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity, Metrics/PerceivedComplexity

    # rubocop:disable Metrics/AbcSize, Metrics/CyclomaticComplexity
    def get_column_map(column, row, via_column: nil)
      base_query = get_base_query(row)
      clazz = as_class(base_query)
      raise ActiveRecord::RecordNotFound, "invalid #{@options[:polymorphic_on]}: #{row[@options[:polymorphic_on]]}" if clazz.nil? # rubocop:disable Metrics/LineLength

      load_column(clazz, column, via_column) do
        relevant_rows = rows
        relevant_rows = relevant_rows.select { |r| r[@options[:polymorphic_on]] == clazz.name } if @options[:polymorphic_on]
        row_keys = Set.new(relevant_rows.pluck(column[0]).compact)

        # In :eager mode, requesting the primary column triggers loading of all columns
        row_keys |= eager_load_columns(base_query, relevant_rows) if @options[:mode] == :eager && column == @primary_column

        # Load data for the requested column
        loaded_hash = load_column_data(column, base_query, row_keys)

        # In :lazy mode, the corresponding primary_column data is loaded with each column
        load_column_data(primary_column, base_query, loaded_hash.values) if @options[:mode] == :lazy && column != @primary_column # rubocop:disable Metrics/LineLength
      end
    end
    # rubocop:enable Metrics/AbcSize, Metrics/CyclomaticComplexity

    def load_column_data(column, base_query, keys)
      data = if column == @primary_column
              base_query.where(column[1] => keys).index_by do |row|
                transform_key(row[column[1]])
              end
            else
              base_query.where(column[1] => keys).pluck(column[1], @primary_column[1]).map do |k, v|
                [transform_key(k), v]
              end.to_h
            end
      add_to_column(column, as_class(base_query), data)
      data
    end

    def add_to_column(column, clazz, entries)
      @maps[column] ||= {}
      cache = @maps[column][clazz] ||= {}
      cache.merge! entries
      cache
    end

    def as_class(clazz)
      clazz.is_a?(ActiveRecord::Relation) ? clazz.model : clazz
    end

    def get_base_query(row)
      return row if row.is_a?(Class) || row.is_a?(ActiveRecord::Relation)
      return @clazz unless @options[:polymorphic_on]

      @clazz.find { |cls| cls.name == row[@options[:polymorphic_on]] }
    end

    def transform_key(key)
      key.nil? ? key : key.to_s
    end

    private

    def load_column(clazz, column, request_column)
      lkey = loaded_key(clazz, column, request_column)
      unless @loaded_columns[lkey]
        yield
        @loaded_columns[lkey] = true
      end
      @maps[column][clazz]
    end

    def loaded_key(clazz, column, request_column)
      key_column = @options[:mode] == :eager ? column : request_column || column
      [*key_column, clazz]
    end

    def eager_load_columns(base_query, relevant_rows)
      additional_keys = Set.new
      @columns.each do |column|
        next if column == primary_column

        loaded_col = load_column_data(column, base_query, relevant_rows.pluck(column[0]).compact.uniq)
        additional_keys |= loaded_col.values
      end
      additional_keys
    end
  end
end
