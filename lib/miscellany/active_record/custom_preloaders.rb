# Example Usage (Preloading items with reference to the same Polymorphic Object):
#
# has_many :related_objects, -> (self) { where(poly_type: self.poly_type, poly_id: self.poly_id) }, preloader: 'RelatedObjectPreloader'
#
# class RelatedObjectPreloader < ActiveRecord::Associations::Preloader::Association
#   def run(preloader)
#     @preloaded_records = []
#     owners.group_by(&:poly_type).each do |type, owner_group|
#       ids = owner_group.map(&:poly_id)
#
#       ids_to_priors = {}
#       scope = Poly.scope_for_association.where(poly_type: self.poly_type, poly_id: self.poly_id)
#       scope.find_each do |pa|
#         ids_to_priors[pa.poly_id] ||= []
#         ids_to_priors[pa.poly_id] << pa
#         @preloaded_records << pa
#       end
#
#       owner_group.each do |owner|
#         priors = ids_to_priors[owner.poly_id] || []
#
#         association = owner.association(reflection.name)
#         association.loaded!
#         association.target = priors
#
#         # association.set_inverse_instance(record)
#       end
#     end
#   end
# end
#
module Miscellany
  module CustomPreloaders # TODO Write Specs
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
end
