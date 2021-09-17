# Add support for creating arbitrary associations when using ActiveRecord
# Adds a `prefetch` method to ActiveRecord Queries.
#   This method accepts a Hash. The keys of the Hash represent how the Association will be made available.
#   The values of the Hash may be an array of [Symbol, Relation] or another (filtered) Relation.
#   Objects are queried from an existing Association on the model. This Association is detemrined
#   by either the Symbol when an array is passed, or by finding an Assoication for the passed Relation's model
#
# NOTICE: This implementation is NOT COMPLETE by itself - it depends on Goldiloader
#   to detect the use of the virtual associations and prevent N+1s. We were already using
#   Goldiloader, so this made sense. If this module is ever needed stand-alone,
#   the following options have been identified:
#     1. Extend ActiveRecordRelationPatch#exec_queries to execute an ActiveRecord::Associations::Preloader
#        that will load the related objects
#     2. Duplicates the relevant snippets from Goldiloader into this module. See Goldiloader::AutoIncludeContext
#   The current Goldiloader implementation uses Option 1 internally, but also makes the relations lazy - even
#     if you define a prefetch, it won't actually be loaded until you attempt to access it on one of the models.
module Miscellany
  module ArbitraryPrefetch
    ACTIVE_RECORD_VERSION = ::Gem::Version.new(::ActiveRecord::VERSION::STRING).release
    PRE_RAILS_6_2 = ACTIVE_RECORD_VERSION < ::Gem::Version.new('6.2.0')

    class PrefetcherContext
      attr_accessor :model, :target_attribute
      attr_reader :options

      def initialize(model, opts)
        @options = opts
        @model = model
        @source_key = opts[:relation]
        @target_attribute = opts[:attribute]
        @queryset = opts[:queryset]
        @models = []
      end

      def link_models(models)
        Array(models).each do |m|
          @models << m

          # assoc = PrefetchAssociation.new(m, self, reflection)
          assoc = reflection.association_class.new(m, reflection)
          m.send(:association_instance_set, target_attribute, assoc)

          m.instance_eval <<-CODE, __FILE__, __LINE__ + 1
            def #{target_attribute}
              association(:#{target_attribute}).reader
            end
          CODE
        end
      end

      def reflection
        @reflection ||= begin
          queryset = @queryset
          source_refl = model.reflections[@source_key.to_s]
          scope = lambda {|*_args|
            qs = queryset
            qs = qs.merge(source_refl.scope_for(model.unscoped)) if source_refl.scope
            qs
          }
          ActiveRecord::Reflection.create(
            options[:type],
            @target_attribute,
            scope,
            source_refl.options.merge(
              class_name: source_refl.class_name,
              inverse_of: nil
            ),
            model
          )
        end
      end
    end

    module ActiveRecordBasePatch
      extend ActiveSupport::Concern

      included do
        class << self
          delegate :prefetch, to: :all
        end
      end
    end

    module ActiveRecordRelationPatch
      def exec_queries
        return super if loaded?

        records = super
        (@values[:prefetches] || {}).each do |_key, opts|
          pfc = PrefetcherContext.new(model, opts)
          pfc.link_models(records)

          unless defined?(Goldiloader)
            if PRE_RAILS_6_2
              ::ActiveRecord::Associations::Preloader.new.preload(records, [opts[:attribute]])
            else
              ::ActiveRecord::Associations::Preloader.new(records: records, associations: [opts[:attribute]]).call
            end
          end
        end
        records
      end

      def prefetch(**kwargs)
        spawn.add_prefetches!(kwargs)
      end

      def add_prefetches!(kwargs)
        return unless kwargs.present?

        assert_mutability!
        @values[:prefetches] ||= {}
        kwargs.each do |attr, opts|
          @values[:prefetches][attr] = normalize_options(attr, opts)
        end
        self
      end

      def normalize_options(attr, opts)
        norm = if opts.is_a?(Array)
            { relation: opts[0], queryset: opts[1] }
          elsif opts.is_a?(ActiveRecord::Relation)
            rel_name = opts.model.name.underscore
            rel = (model.reflections[rel_name] || model.reflections[rel_name.pluralize])&.name
            { relation: rel, queryset: opts }
          else
            opts
        end

        norm[:attribute] = attr
        norm[:type] ||= (attr.to_s.pluralize == attr.to_s) ? :has_many : :has_one

        norm
      end
    end

    module ActiveRecordMergerPatch
      def merge
        super.tap do
          merge_prefetches
        end
      end

      private

      def merge_prefetches
        relation.add_prefetches!(other.values[:prefetches])
      end
    end

    module ActiveRecordPreloaderPatch
      if ACTIVE_RECORD_VERSION >= ::Gem::Version.new('6.0.0')
        def grouped_records(association, records, polymorphic_parent)
          h = {}
          records.each do |record|
            next unless record
            reflection = record.class._reflect_on_association(association)
            reflection ||= record.association(association)&.reflection
            next if polymorphic_parent && !reflection || !record.association(association).klass
            (h[reflection] ||= []) << record
          end
          h
        end
      end
    end

    module ActiveRecordReflectionPatch
      def check_preloadable!
        return if scope && scope.arity < 0
        super
      end
    end

    def self.install
      ::ActiveRecord::Base.include(ActiveRecordBasePatch)

      ::ActiveRecord::Relation.prepend(ActiveRecordRelationPatch)
      ::ActiveRecord::Relation::Merger.prepend(ActiveRecordMergerPatch)

      ::ActiveRecord::Associations::Preloader.prepend(ActiveRecordPreloaderPatch)

      ::ActiveRecord::Reflection::AssociationReflection.prepend(ActiveRecordReflectionPatch)

      return unless defined? ::Goldiloader

      ::Goldiloader::AssociationLoader.module_eval do
        def self.has_association?(model, association_name)
          model.association(association_name)
          true
        rescue ::ActiveRecord::AssociationNotFoundError => _err
          false
        end
      end
    end
  end
end
