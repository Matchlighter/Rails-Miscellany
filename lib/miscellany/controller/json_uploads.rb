module Miscellany
  module JsonUploads
    extend ActiveSupport::Concern

    # This hackery allows using JSON params along with file-uploads
    # On the frontend, use MultiPart form data, and add _parameters as an entry
    def process_action(*)
      json_param = request.request_parameters[:_parameters]
      if json_param.present?
        parsed = JSON.parse(json_param)
        overlapping_params = request.request_parameters.slice(*(request.request_parameters.keys & parsed.keys))
        _merge_json_params(parsed, overlapping_params)

        request.parameters.merge! parsed
        request.request_parameters.merge! parsed
      end
      super
    end

    private

    def _wrapper_enabled?
      (_wrapper_options.format.include?(:json) && request.request_parameters[:_parameters].present?) || super
    end

    def _merge_json_params(base, layer)
      if base.is_a?(Array) && (layer.is_a?(Hash) || layer.is_a?(Array))
        base.each_with_index.map do |v, i|
          over_key = layer.is_a?(Hash) ? i.to_s : i
          _merge_json_params(v, layer[over_key])
        end
      elsif base.is_a?(Hash) && layer.is_a?(Hash)
        base.each do |k, v|
          base[k] = _merge_json_params(v, layer[k])
        end
        layer.merge(base)
      else
        Rails.logger.warn 'Duplicate parameter passed' if base.present? && layer.present?
        layer.presence || base
      end
    end
  end
end