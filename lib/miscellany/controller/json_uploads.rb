module Miscellany
  module JsonUploads
    extend ActiveSupport::Concern

    # This hackery allows using JSON params along with file-uploads
    # On the frontend, use MultiPart form data, and add _parameters as an entry
    def params
      if @_params.nil?
        params_obj = @_params = super
        phash = params_obj.instance_variable_get(:@parameters)
        if phash[:_parameters].present?
          json_layer = JSON.parse(phash.delete(:_parameters))
          shared_keys = phash.keys & json_layer.keys
          main_layer = phash.slice(*shared_keys)
          merge_params(json_layer, main_layer)
          phash.merge!(json_layer)
        end
      end
      @_params
    end

    private

    def merge_params(base, layer)
      if base.is_a?(Array) && (layer.is_a?(Hash) || layer.is_a?(Array))
        base.each_with_index.map do |v, i|
          over_key = layer.is_a?(Hash) ? i.to_s : i
          merge_params(v, layer[over_key])
        end
      elsif base.is_a?(Hash) && layer.is_a?(Hash)
        base.each do |k, v|
          base[k] = merge_params(v, layer[k])
        end
        layer.merge(base)
      else
        Rails.logger.warn 'Duplicate parameter passed' if base.present? && layer.present?
        layer.presence || base
      end
    end
  end
end