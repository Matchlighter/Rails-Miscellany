module Miscellany
  module SpaRender
    extend ActiveSupport::Concern

    def render(*args, **kwargs)
      if kwargs[:spa].present?
        js_env(kwargs.delete(:env))
        kwargs[:template] ||= 'miscellany/spa_page'
        kwargs[:locals] ||= {}
        kwargs[:locals][:pack_name] ||= kwargs.delete(:spa)
        kwargs[:formats] = [:html]
        super(*args, **kwargs)
      else
        super
      end
    end
  end
end
