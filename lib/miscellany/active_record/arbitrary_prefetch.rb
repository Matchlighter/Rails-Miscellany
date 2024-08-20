# Add support for creating arbitrary associations when using ActiveRecord
# Adds a `prefetch` method to ActiveRecord Queries.
#   This method accepts a Hash. The keys of the Hash represent how the Association will be made available.
#   The values of the Hash may be an array of [Symbol, Relation] or another (filtered) Relation.
#   Objects are queried from an existing Association on the model. This Association is detemrined
#   by either the Symbol when an array is passed, or by finding an Assoication for the passed Relation's model
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
          pass_opts = source_refl.options.merge(
            class_name: source_refl.class_name,
            inverse_of: nil,
            arbitrary_source_reflection: source_refl,
          )
          if source_refl.is_a?(ActiveRecord::Reflection::ThroughReflection)
            pass_opts[:source] = source_refl.source_reflection_name
          end
          ActiveRecord::Reflection.create(
            options[:type],
            @target_attribute,
            scope,
            pass_opts,
            model
          )
        end
      end
    end

    module ActiveRecordPatches
      module BasePatch
        extend ActiveSupport::Concern

        included do
          class << self
            delegate :prefetch, to: :all
          end
        end
      end

      module RelationPatch
        def exec_queries
          return super if loaded?

          records = super
          (@values[:prefetches] || {}).each do |_key, opts|
            pfc = PrefetcherContext.new(model, opts)
            pfc.link_models(records)

            unless defined?(Goldiloader) && Goldiloader.enabled?
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
            @values[:prefetches][attr] = normalize_prefetch_options(attr, opts)
          end
          self
        end

        def normalize_prefetch_options(attr, opts)
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

      module Relation
        module MergerPatch
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
      end

      module Associations
        if ACTIVE_RECORD_VERSION >= ::Gem::Version.new('7.0.0')
          module Preloader
            module BranchPatch
              def grouped_records
                h = {}
                polymorphic_parent = !root? && parent.polymorphic?
                source_records.each do |record|
                  next unless record
                  reflection = record.class._reflect_on_association(association)
                  reflection ||= record.association(association)&.reflection rescue nil
                  next if polymorphic_parent && !reflection || !record.association(association).klass
                  (h[reflection] ||= []) << record
                end
                h
              end
            end
          end
        elsif ACTIVE_RECORD_VERSION >= ::Gem::Version.new('6.0.0')
          module PreloaderPatch
            def grouped_records(association, records, polymorphic_parent)
              h = {}
              records.each do |record|
                next unless record
                reflection = record.class._reflect_on_association(association)
                reflection ||= record.association(association)&.reflection rescue nil
                next if polymorphic_parent && !reflection || !record.association(association).klass
                (h[reflection] ||= []) << record
              end
              h
            end
          end
        end
      end

      module Reflection
        module AssociationReflectionPatch
          def check_preloadable!
            return if scope && scope.arity < 0
            super
          end
        end

        module ThroughReflectionPatch
          def check_validity!
            return if options[:arbitrary_source_reflection] # Rails already checked the base relation, we're good
            super
          end
        end
      end
    end

    def self.apply_patches(mod, install_base, base_module: nil)
      return unless mod.is_a?(Module)

      base_module ||= mod

      if mod.name.end_with? "Patch"
        base_full_name = base_module.to_s
        mod_full_name = mod.to_s
        mod_rel_name = mod_full_name.sub(base_full_name, '')
        mod_rel_bits = mod_rel_name.split('::').select(&:present?).map do |bit|
          bit.end_with?('Patch') ? bit[0..-6] : bit
        end
        final_mod_name = [install_base, *mod_rel_bits].select(&:present?).join("::")
        install_mod = final_mod_name.constantize

        if mod.is_a?(ActiveSupport::Concern)
          install_mod.include(mod)
        else
          install_mod.prepend(mod)
        end
      end

      mod.constants.map {|const| mod.const_get(const) }.each do |const|
        apply_patches(const, install_base, base_module: base_module || mod)
      end
    end

    def self.install
      apply_patches(ActiveRecordPatches, ::ActiveRecord)

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
