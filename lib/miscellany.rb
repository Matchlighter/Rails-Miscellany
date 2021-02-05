
Dir[File.dirname(__FILE__) + "/miscellany/**/*.rb"].each { |file| require file }

module Miscellany

  if defined?(Rails)
    class Engine < ::Rails::Engine
    end
  end
end
