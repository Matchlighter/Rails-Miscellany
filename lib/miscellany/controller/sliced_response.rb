require_relative './http_error_handling'

module Miscellany
  module SlicedResponse
    extend ActiveSupport::Concern

    include HttpErrorHandling

    def slice_results(queryset, **kwargs)
      @sliced_data = sliced_json(queryset, **kwargs) { |x| x }
    end

    # rubocop:disable Metrics/ParameterLists
    def sliced_json(
      queryset, slice_params = params,
      max_size: 50, default_size: 25, allow_all: false,
      default_sort: nil, valid_sorts: nil,
      &blk
    )
      valid_sorts ||= queryset.column_names if queryset.respond_to?(:column_names)
      valid_sorts ||= []
      normalized_sorts = normalize_sort_options(valid_sorts, default: default_sort)

      slice = Slice.build(
        queryset, slice_params,
        default_page_size: default_size,
        item_transformer: blk,
        max_size: max_size,
        default_size: default_size,
        allow_all: allow_all,
        valid_sorts: normalized_sorts,
      )

      slice.render_json
    end
    # rubocop:enable Metrics/ParameterLists

    def as_sliced_json(queryset, slice: nil, total_count: nil, &blk)
      slice = Slice.build(queryset, slice, total_count: total_count, item_transformer: blk)
      slice.render_json
    end

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

    def normalize_sort_options(sorts, default: nil)
      norm_sorts = { }

      sorts.each do |s|
        if s.is_a?(Hash)
          s.each do |k,v|
            sort_hash = normalize_sort(v, key: k)
            norm_sorts[k] = sort_hash
          end
        else
          sort_hash = normalize_sort(s)
          norm_sorts[sort_hash[:column]] = sort_hash
          # default ||= sort_hash
        end
      end

      if default.present?
        norm_default = normalize_sort(default)
        reference = norm_sorts[norm_default[:key].to_s] || norm_default
        norm_sorts[:default] = {
          key: reference[:key],
          column: reference[:column],
          order: norm_default[:order] || reference[:order],
        }
      end

      norm_sorts
    end

    def normalize_sort(sort, key: nil)
      sort = sort.to_s if sort.is_a?(Symbol)
      if sort.is_a?(Array)
        sort = { **normalize_sort(sort[0]), **(sort[1] || {}) }
      elsif sort.is_a?(String)
        m = sort.match(/^([\w\.]+)(?: (ASC|DESC)(!?))?$/)
        sort = { column: m[1], order: m[2], force_order: m[3].present? }.compact
      elsif sort.is_a?(Proc)
        sort = { column: sort }
      end
      sort[:key] = key || sort[:column]
      sort.compact
    end

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

            slice[:sort] = parse_and_validate_sorts(arg[:sort], options[:valid_sorts])
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

      def self.parse_and_validate_sorts(sortstr, sorts_map, silent_failure: true)
        (sortstr || '').split(',').map do |s|
          m = s.strip.match(/^(\w+)(?: (ASC|DESC))?$/)

          if m.nil?
            next if silent_failure
            raise HttpErrorHandling::HttpError, message: 'Could not parse sort parameter'
          end

          resolved_sort = sorts_map[m[1]]
          unless resolved_sort.present?
            next if silent_failure
            raise HttpErrorHandling::HttpError, message: 'Could not parse sort parameter'
          end

          sort = resolved_sort.dup
          sort[:order] = m[2] if m[2].present? && !sort[:force_order]
          sort
        end.compact.presence || [sorts_map[:default]].compact
      end

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
            apply_ar_sort(items).limit(limit).offset(offset)
          end
        end
      end

      def slice_bounds
        [slice_start, slice_end == -1 ? nil : slice_end]
      end

      def apply_ar_sort(qset)
        if sort.present?
          sorts = [ *Array(self.sort) ]
          sorts << options[:valid_sorts][:default] if options.dig(:valid_sorts, :default).present?

          sorts.reduce(qset) do |qset, sort|
            order = sort[:order] || 'ASC'
            if sort[:column].is_a?(Proc)
              sort[:column].call(qset, order)
            else
              desired_nulls = (sort[:nulls] || :low).to_s.downcase.to_sym
              nulls = case desired_nulls
              when :last
                'LAST'
              when :first
                'FIRST'
              else
                (desired_nulls == :high) == (order.to_s.upcase == 'DESC') ? 'FIRST' : 'LAST'
              end
              qset.order("#{sort[:column]} #{order} NULLS #{nulls}")
            end
          end
        else
          qset
        end
      end
    end

    module JbuilderTemplateExt
      def partial!(*args, **kwargs, &blk)
        kwargs[:block] = blk if blk.present?
        super(*args, **kwargs)
      end
    end

    def self.install_extensions
      ::JbuilderTemplate.prepend JbuilderTemplateExt
    end
  end
end
