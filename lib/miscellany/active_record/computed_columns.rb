
module Miscellany
  module ComputedColumns
    module ActiveRecordBasePatch
      extend ActiveSupport::Concern

      included do
        class << self
          delegate :with_computed, to: :all
        end
      end

      class_methods do
        def define_computed(key, dirblk = nil, &blk)
          blk ||= dirblk
          @defined_computeds ||= {}
          @defined_computeds[key] = blk
        end

        def get_defined_computed(key)
          @defined_computeds ||= {}
          @defined_computeds[key] || superclass.try(:get_defined_computed, key)
        end
      end
    end

    module ActiveRecordRelationPatch
      def with_computed(*args, **kwargs)
        entries = { **kwargs }
        args.each do |k|
          entries[k] = []
        end

        entries.reduce(self) do |query, (k, v)|
          comp = model.get_defined_computed(k)
          raise "Undefined ComputedColum :#{k}" if comp.nil?

          builder = ComputedBuilder.new(k, v, &comp)
          builder.apply(query)
        end
      end
    end

    class ComputedBuilder
      def initialize(key, args, &blk)
        @key = key
        @args = args.is_a?(Array) ? args : [args]
        @block = blk
        @compiled = {}
      end

      %i[select join_condition query].each do |m|
        define_method(m) do |arg=:not_given, &blk|
          raise "Must provide either a value or a block" if arg != :not_given && blk
          raise "Must provide either a value or a block" if arg == :not_given && !blk

          if arg == :not_given
            arg = blk.call
          end

          @compiled[m] = arg
        end
      end

      def apply(q)
        instance_exec(*@args, &@block)

        c = @compiled
        raise "defined_computed: query must be provided" unless c[:query]

        join_name = @key.to_s
        base_table_name = current_table_from_scope(q)
        c[:join_condition] ||= "COMPUTED.id = #{base_table_name}.id"
        c[:select] ||= "#{join_name}.value AS #{@key}"

        q = q.select("#{base_table_name}.*") if !q.values[:select].present?

        select_statement = c[:select].gsub('COMPUTED', join_name)
        join_condition = c[:join_condition].gsub('COMPUTED', join_name)
        join_query = c[:query]
        join_query = join_query.to_sql if join_query.respond_to?(:to_sql)

        q.select(select_statement).joins("LEFT OUTER JOIN (#{join_query}) #{join_name} ON #{join_condition}")
      end

      protected

      def current_table_from_scope(q)
        current_table = q.current_scope.arel.source.left

        case current_table
        when Arel::Table
          current_table.name
        when Arel::Nodes::TableAlias
          current_table.right
        else
          fail
        end
      end
    end

    def self.install
      ::ActiveRecord::Base.include(ActiveRecordBasePatch)
      ::ActiveRecord::Relation.prepend(ActiveRecordRelationPatch)
    end
  end
end
