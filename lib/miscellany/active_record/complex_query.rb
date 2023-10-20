module Miscellany
  class ComplexQuery
    attr_reader :options

    def initialize(options)
      @options = options.with_indifferent_access
    end

    def count
      res = ActiveRecord::Base.connection.execute(build_count_query)
      res[0].to_h.values[0]
    end

    def page(page, page_size: 40)
      total_items = count

      page = page.to_i || 1
      page = 1 if page < 1
      page_size = page_size.to_i
      page_size = 10 if page_size < 2
      offset = (page - 1) * page_size

      psql = sql
      psql += " LIMIT #{page_size} OFFSET #{offset}"

      records = ActiveRecord::Base.connection.exec_query(psql).to_a
      augment_batch(records)

      {
        page: page,
        total_count: total_items,
        page_count: (total_items.to_f / page_size).ceil,
        page_size: page_size,
        sort: parsed_sort&.map do |s|
          "#{s[:key] || s[:column]} #{s[:order] || 'ASC'}"
        end&.join(', '),
        records: records,
      }
    end

    def slice(start, length, raw_sort: nil)
      psql = build_query
      if raw_sort.present?
        psql += " ORDER BY #{raw_sort}"
      elsif sort_sql.present?
        psql += " ORDER BY #{sort_sql}"
      end
      psql += " LIMIT #{length} OFFSET #{start}"
      records = ActiveRecord::Base.connection.exec_query(psql).to_a
      records = records.map(&:with_indifferent_access)
      augment_batch(records)
      records
    end

    def in_batches(of: 1000)
      conn = ActiveRecord::Base.connection
      tbl = "#{self.class.name.split('::').last.underscore}_#{SecureRandom.hex[0..10]}"

      conn.execute("CREATE TEMP TABLE #{tbl} AS (#{sql})")

      offset = 0
      loop do
        batch = ActiveRecord::Base.connection.exec_query(
          "SELECT * FROM #{tbl} LIMIT #{of} OFFSET #{offset}",
        )
        batch = batch.map(&:with_indifferent_access)
        augment_batch(batch)
        yield batch
        offset += of
        break if batch.empty?
      end
    ensure
      conn.execute("DROP TABLE IF EXISTS #{tbl}")
    end

    def find_each(batch_size: 1000, &block)
      in_batches(of: batch_size) do |batch|
        batch.each(&block)
      end
    end

    def sql
      sql = build_query
      sql += " ORDER BY #{sort_sql}" if sort_sql.present?
      sql
    end

    def valid_sort?(sort)
      sort_parser.valid?(sort)
      return false unless sort.present?
    end

    protected

    def augment_batch(records); end

    def build_query; end

    def build_count_query; end

    def sort_sql
      return options[:raw_sort] if options[:raw_sort].present? && !options[:raw_sort].is_a?(ActionController::Parameters)
      return nil unless options[:sort].present?

      Miscellany::SortLang.sqlize(parsed_sort)
    end

    def parsed_sort
      return nil if options[:raw_sort].present?
      @parsed_sort ||= sort_parser.parse(options[:sort])
    end

    def valid_sorts
      return self.class::SORTABLE_COLUMNS.with_indifferent_access if defined?(self.class::SORTABLE_COLUMNS)
    end

    def sort_parser
      @sort_parser ||= Miscellany::SortLang::Parser.new(valid_sorts || {})
    end

    def sanitize_sql(*args)
      ApplicationRecord.sanitize_sql(args)
    end

    def filters
      options[:filters] || {}
    end

    def join_filters(*filters)
      filters.flatten.select(&:present?).map { |q| "(#{q})" }.join(' AND ').presence || '1=1'
    end

    def date_filter(column, range, timezone: nil)
      range = _parse_datetime_range(range)

      range = range.map{|dt| dt&.in_time_zone(timezone) } if timezone.present?
      range[0] = range[0]&.beginning_of_day
      range[1] = range[1]&.end_of_day

      datetime_filter(column, range)
    end

    def datetime_filter(column, range)
      range = _parse_datetime_range(range)

      start_date = range[0]
      end_date = range[1]

      if end_date.present? && start_date.present?
        "#{column} BETWEEN '#{start_date}' AND '#{end_date}'"
      elsif start_date.present?
        "#{column} >= '#{start_date}'"
      elsif end_date.present?
        "#{column} <= '#{end_date}'"
      end
    end

    def _parse_datetime_range(range)
      range = [filters["#{key}_start"], filters["#{key}_end"]] if range.is_a?(String) || range.is_a?(Symbol)
      range = range.map{|v| _parse_datetime(v)}
      range
    end

    def _parse_datetime(value)
      return DateTime.parse(value) if value.is_a?(String)
      value
    end
  end
end
