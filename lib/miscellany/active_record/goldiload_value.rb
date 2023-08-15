module Miscellany
  module GoldiloadValue
    attr_accessor :goldi_values

    def goldiload_value(key, &blk)
      return goldi_values[key] if goldi_values && goldi_values.key?(key)

      models = auto_include_context.models
      loaded = blk.call(models)
      models.each do |m|
        (m.goldi_values ||= {})[key] = loaded.key?(m) ? loaded[m] : loaded[m&.id]
      end

      goldi_values[key]
    end

    def self.install
      ::ActiveRecord::Base.include(GoldiloadValue)
    end
  end
end
