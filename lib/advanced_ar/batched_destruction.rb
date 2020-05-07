module AdvancedAR::BatchedDestruction
  extend ActiveSupport::Concern

  included do
    define_model_callbacks :bulk_destroy
    define_model_callbacks :destroy_batch

    before_destroy_batch do
      # TODO Delete Dependant Relations
      model_class.reflections.each do |name, reflection|
        options = reflection.options
      end
    end
  end

  class_methods do
    def bulk_destroy(**kwargs)
      return to_sql
      bulk_destroy_internal(self, **kwargs)
    end

    # Hook for performing the actual deletion of items, may be used to facilitate soft-deletion.
    # Must not call destroy().
    # Default implementation is to delete the batch using delete_all(id: batch_ids).
    def destroy_bulk_batch(batch, options)
      delete_ids = batch.map(&:id)
      where(id: delete_ids).delete_all()
    end

    private

    def bulk_destroy_internal(items, **kwargs)
      options = {}
      options.merge!(kwargs)
      ClassCallbackExector.run_callbacks(model_class, :bulk_destroy, options: options) do
        if items.respond_to?(:find_in_batches)
          items.find_in_batches do |batch|
            _destroy_batch(batch, options)
          end
        else
          _destroy_batch(items, options)
        end
      end
    end

    def _destroy_batch(batch, options)
      ClassCallbackExector.run_callbacks(model_class, :destroy_batch, {
        model_class: model_class,
        batch: batch,
      }) do
        model_class.destroy_bulk_batch(batch, options)
      end
    end

    private

    def model_class
      try(:model) || self
    end
  end

  def destroy(*args, legacy: false, **kwargs)
    if legacy
      super(*args)
    else
      self.class.send(:bulk_destroy_internal, [self], **kwargs)
    end
  end

  private

  # These classes are some Hackery to allow us to use callbacks against the Model classes instead of Model instances
  class ClassCallbackExector
    include ActiveSupport::Callbacks

    attr_reader :callback_class
    delegate :__callbacks, to: :callback_class
    delegate_missing_to :callback_class

    def initialize(cls, env)
      @callback_class = cls
      env.keys.each do |k|
        define_singleton_method(k) do
          env[k]
        end
      end
      @options = options
    end

    def self.run_callbacks(cls, callback, env={}, &blk)
      new(cls, env).run_callbacks(callback, &blk)
    end
  end
end
