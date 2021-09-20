
require "active_support/lazy_load_hooks"

Dir[File.dirname(__FILE__) + "/miscellany/**/*.rb"].each { |file| require file }

module Miscellany

  if defined?(Rails)
    class Engine < ::Rails::Engine
    end
  end

  ActiveSupport.on_load(:active_record) do
    Miscellany::CustomPreloaders.install
    Miscellany::ArbitraryPrefetch.install
    Miscellany::ComputedColumns.install
  end
end
