module Miscellany
  module SortLang

    # Normalized Format: {
    #   key: string,
    #   column: string,
    #   order: 'DESC' | 'ASC',
    #   force_order?: boolean, # Prevent overriding order
    #   nulls?: 'high' | 'low' | 'first' | 'last',
    # }
    def self.normalize_sort(sort, key: nil)
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

    def self.sqlize(sorts)
      seen_sorts = Set.new

      # Only include each sort key/"column" once
      sorts = sorts.select do |sort|
        sid = sort[:key] || sort[:column]
        next true unless sid.present?

        if seen_sorts.include?(sid)
          false
        else
          seen_sorts << sid
          true
        end
      end

      sorts.map do |sort|
        order = sort[:order] || 'ASC'
        if sort[:column].is_a?(Proc)
          sort[:column].call(order)
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
          "#{sort[:column]} #{order} NULLS #{nulls}"
        end
      end.join(', ')
    end

    class Parser
      class SortParsingError < StandardError; end

      attr_reader :default_sorts

      def initialize(valid_sorts, default: nil)
        @sorts_map = normalize_sort_options(valid_sorts)

        @default_sorts = []

        parsed_defaults = normalize_sort_options(Array(default))
        parsed_defaults.each do |k,v|
          @sorts_map[k] ||= v
        end
        @default_sorts = parsed_defaults.keys.map do |k|
          @sorts_map[k]
        end
      end

      def valid?(sortstr)
        parse(sortstr, ignore_errors: false)
        true
      rescue SortParsingError
        false
      end

      def parse(sortstr, ignore_errors: true, default: :true)
        sorts = (sortstr || '').split(',').map do |s|
          m = s.strip.match(/^(\w+)(?: (ASC|DESC))?$/)

          if m.nil?
            next if ignore_errors
            raise SortParsingError, message: 'Could not parse sort parameter'
          end

          resolved_sort = @sorts_map[m[1]]
          unless resolved_sort.present?
            next if ignore_errors
            raise SortParsingError, message: 'Could not parse sort parameter'
          end

          sort = resolved_sort.dup
          sort[:order] = m[2] if m[2].present? && !sort[:force_order]
          sort
        end

        if default == :append || default && !sorts.compact.present?
          sorts.push(*self.default_sorts)
        end

        sorts.compact.presence
      end

      protected

      def normalize_sort_options(sorts)
        norm_sorts = { }

        sorts.each do |s|
          if s.is_a?(Hash)
            s.each do |k,v|
              k = k.to_s
              sort_hash = normalize_sort(v, key: k)
              norm_sorts[k] = sort_hash
            end
          else
            sort_hash = normalize_sort(s)
            norm_sorts[sort_hash[:column]] = sort_hash
          end
        end

        norm_sorts
      end

      def normalize_sort(*args, **kwargs)
        SortLang.normalize_sort(*args, **kwargs)
      end
    end

  end
end
