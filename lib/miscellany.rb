
# Required explicitly rather than relying on the host app to have loaded them
# first: the files below reference ActiveRecord and ActiveSupport at load time.
require "active_support"
require "active_support/core_ext"
require "active_support/lazy_load_hooks"
require "active_record"
require "bigdecimal"
require "bigdecimal/util"

# Sorted so load order does not depend on the filesystem.
Dir[File.dirname(__FILE__) + "/miscellany/**/*.rb"].sort.each { |file| require file }

module Miscellany

  if defined?(Rails)
    class Engine < ::Rails::Engine
    end
  end

  ActiveSupport.on_load(:active_record) do
    Miscellany::CustomPreloaders.install
    Miscellany::ArbitraryPrefetch.install
    Miscellany::ComputedColumns.install
    Miscellany::GoldiloadValue.install
  end
end
