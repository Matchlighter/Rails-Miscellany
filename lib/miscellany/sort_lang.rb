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
      sorts.map do |sort|
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
          "#{sort[:column]} #{order} NULLS #{nulls}"
        end
      end.join(', ')
    end

    class Parser
      class SortParsingError < StandardError; end

      def initialize(valid_sorts, default: nil)
        @sorts_map = normalize_sort_options(valid_sorts, default: default)
      end

      def default
        @sorts_map[:default]
      end

      def valid?(sortstr)
        parse(sortstr, ignore_errors: false)
        true
      rescue SortParsingError
        false
      end

      def parse(sortstr, ignore_errors: true)
        (sortstr || '').split(',').map do |s|
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
        end.compact.presence
      end

      protected

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

      def normalize_sort(*args, **kwargs)
        SortLang.normalize_sort(*args, **kwargs)
      end
    end

  end
end
