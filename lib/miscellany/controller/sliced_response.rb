require_relative './http_error_handling'

module Miscellany
  module SlicedResponse
    extend ActiveSupport::Concern

    include HttpErrorHandling

    # Deprecated
    def slice_results(queryset, **kwargs)
      @sliced_data = sliced_json(queryset, **kwargs) { |x| x }
    end

    def sliced_json(
      queryset, slice_params = params,
      max_size: 50, default_size: 25, allow_all: false,
      default_sort: nil, valid_sorts: nil,
      &blk
    )
      valid_sorts ||= queryset.column_names if queryset.respond_to?(:column_names)
      valid_sorts ||= []

      if !valid_sorts.present? && defined?(Miscellany::ComplexQuery) && queryset.is_a?(Miscellany::ComplexQuery)
        sort_parser = queryset.send(:sort_parser)
      else
        sort_parser = Miscellany::SortLang::Parser.new(valid_sorts, default: default_sort)
      end

      slice = Slice.build(
        queryset, slice_params,
        default_page_size: default_size,
        item_transformer: blk,
        max_size: max_size,
        default_size: default_size,
        allow_all: allow_all,
        sort_parser: sort_parser,
      )

      slice.render_json
    end

    # Format the given data as a JSON slice, but doesn't expect slicing parameters
    def as_sliced_json(queryset, slice: nil, total_count: nil, &blk)
      slice = Slice.build(queryset, slice, total_count: total_count, item_transformer: blk)
      slice.render_json
    end

    # Wrap a Bearcat API instance in a slicing API
    # bearcat_as_sliced_json() do |params|
    #   bearcat_instance.courses(params)
    # end
    def bearcat_as_sliced_json(*args, transform: nil, **kwargs, &blk)
      bearcat_exec = ->(slice) {
        response = blk.call({
          per_page: slice.page_size,
          page: slice.page_number,
        })

        slice.rendered_json[:page_count] = response.page_count

        response
      }
      sliced_json(bearcat_exec, *args, valid_sorts: {}, **kwargs, allow_all: false, &transform)
    end

    private

    class Slice
      attr_accessor :slice_start, :slice_end
      attr_accessor :page_size, :page_number
      attr_accessor :sort

      attr_reader :items
      attr_reader :options

      def initialize(items, options={})
        @items = items
        @options = options
      end

      def self.build(queryset, arg, options={})
        new(queryset, options).tap do |slice|
          if arg.is_a?(Array)
            slice_bounds = arg
          elsif arg.is_a?(String)
            slice_bounds = arg.split(':').map(&:to_i)
          elsif arg.is_a?(Range)
            slice_bounds = arg.minmax
          elsif arg.respond_to? :[]
            if arg[:slice] == 'all' || arg[:page] == 'all'
              slice_bounds = [0, -1]
            elsif arg[:slice].present?
              slice_bounds = arg[:slice].split(':').map(&:to_i)
            else
              page_size = slice[:page_size] = (arg[:page_size] || options[:default_page_size]).to_i
              page_number = slice[:page_number] = (arg[:page] || 1).to_i
              slice_bounds = [(page_number - 1) * page_size, page_number * page_size]
            end

            begin
              slice[:sort] = options[:sort_parser]&.parse(arg[:sort], ignore_errors: true, default: true)
            rescue Miscellany::SortLang::Parser::SortParsingError => e
              raise HttpErrorHandling::HttpError, message: e.message
            end
          end

          if slice_bounds.present?
            slice[:slice_start] = slice_bounds[0]
            slice[:slice_end] = slice_bounds[1]
          end

          if slice[:slice_end] == -1
            raise HttpErrorHandling::HttpError, message: "cannot request whole collection" unless options[:allow_all]
          else
            if options[:max_size] && (slice[:slice_end] - slice[:slice_start]) > [options[:max_size], options[:default_size]].max
              raise HttpErrorHandling::HttpError, message: "cannot request more than #{options[:max_size]} objects"
            end
          end
        end
      end

      def [](key)
        send(key)
      end

      def []=(key, val)
        send(:"#{key}=", val)
      end

      def render_json
        return @rendered_json if defined?(@rendered_json)

        json = @rendered_json = {
          slice_start: slice_start,
          slice_end: slice_end,
        }

        rendered_items

        if page_size.present?
          json[:page] ||= page_number
          json[:page_size] ||= page_size
        end

        if total_item_count.present?
          json[:total_count] ||= total_item_count
          json[:page_count] ||= (total_item_count.to_f / page_size).ceil if page_size.present?
        end

        if sort.present?
          json[:sort] ||= sort.map do |s|
            "#{s[:key] || s[:column]} #{s[:order] || 'ASC'}"
          end.join(', ')
        end

        json[:slice_start] ||= 0
        json[:slice_end] ||= total_item_count

        json[:items] = rendered_items

        json
      end
      def rendered_json; render_json; end

      private

      def rendered_items
        ritems = sliced_items
        ritems = ritems.to_a.map(&options[:item_transformer]) if options[:item_transformer]
        ritems
      end

      def total_item_count
        @total_item_count ||= options[:total_count] || begin
          if items.is_a?(ActiveRecord::Relation)
            items.except(:select).count
          elsif items.respond_to?(:count)
            items.count
          elsif defined?(Miscellany::ComplexQuery) && items.is_a?(Miscellany::ComplexQuery)
            items.count
          else
            nil
          end
        end
      end

      def sliced_items
        @sliced_items ||= begin
          if items.is_a?(Array)
            start, finish = slice_bounds
            if start && finish
              items[start...finish]
            else
              items
            end
          elsif items.is_a?(Proc)
            items.call(self)
          elsif items.is_a?(ActiveRecord::Relation)
            offset, limit = slice_bounds
            limit -= offset unless limit.nil?
            items.order(Arel.sql(sort_sql)).limit(limit).offset(offset).to_a
          elsif defined?(Miscellany::ComplexQuery) && items.is_a?(Miscellany::ComplexQuery)
            offset, limit = slice_bounds
            limit -= offset unless limit.nil?
            query = items.send(:build_query)
            items.slice(offset, limit, raw_sort: sort_sql)
          end
        end
      end

      def slice_bounds
        [slice_start, slice_end == -1 ? nil : slice_end]
      end

      def sort_sql
        sorts = [ *Array(self.sort) ]
        sorts << options[:sort_parser]&.default
        sorts.compact!

        return nil unless sorts.present?

        Miscellany::SortLang.sqlize(sorts)
      end
    end
  end
end
