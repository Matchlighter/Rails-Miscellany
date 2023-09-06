module Miscellany
  module Extensions
    module JBuilder

      # Enables passing blocks to JBuilder `partial!`
      # When a block is given, it will be made available as `block` in the partial
      module JbuilderTemplateExt
        def partial!(*args, **kwargs, &blk)
          kwargs[:block] = blk if blk.present?
          super(*args, **kwargs)
        end
      end

      def self.install
        ::JbuilderTemplate.prepend JbuilderTemplateExt
      end

      begin
        require 'jbuilder'
      rescue LoadError
      end

      install if defined?(::JbuilderTemplate)
    end
  end
end
