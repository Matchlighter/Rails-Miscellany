# Custom (ActiveRecord) Preloaders
Allows specifying a custom "Preloader" for associations.
The preloader is invoked by `preload` and `includes` to load the related association in as few queries as possible.

## Installation
In an Initializer:
```ruby
Miscellany::CustomPreloaders.install
```

## Examples
Example Usage (Preloading items with reference to the same Polymorphic Object).  

The lambda is only called when performing singular access (ie `instance.related_objects`) when not previously preloaded. Without a Custom Preloader, trying `preload(:related_objects)` would throw an error since the lambda is parameterized.  

```ruby
has_many :related_objects, -> (self) { where(poly_type: self.poly_type, poly_id: self.poly_id) }, preloader: 'RelatedObjectPreloader'
```

```ruby
class RelatedObjectPreloader < ActiveRecord::Associations::Preloader::Association
  def run(preloader)
    @preloaded_records = []
    owners.group_by(&:poly_type).each do |type, owner_group|
      ids = owner_group.map(&:poly_id)

      ids_to_priors = {}
      scope = Poly.scope_for_association.where(poly_type: self.poly_type, poly_id: self.poly_id)
      scope.find_each do |pa|
        ids_to_priors[pa.poly_id] ||= []
        ids_to_priors[pa.poly_id] << pa
        @preloaded_records << pa
      end

      owner_group.each do |owner|
        priors = ids_to_priors[owner.poly_id] || []

        association = owner.association(reflection.name)
        association.loaded!
        association.target = priors

        # association.set_inverse_instance(record)
      end
    end
  end
end
```
