module AdvancedAR::CustomPreloaders
  module AssociationBuilderExtension
    def self.build(model, reflection); end

    def self.valid_options
      [:preloader]
    end
  end

  module PreloaderExtension
    def preloader_for(reflection, owners)
      cust_preloader = reflection.options[:preloader]
      if cust_preloader.present?
        cust_preloader = cust_preloader.constantize if cust_preloader.is_a?(String)
        cust_preloader
      else
        super
      end
    end
  end

  def self.install
    ActiveRecord::Associations::Builder::Association.extensions << AssociationBuilderExtension
    ActiveRecord::Associations::Preloader.prepend(CustomPreloaders::PreloaderExtension)
  end
end
