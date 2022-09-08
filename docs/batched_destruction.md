# BatchedDestruction
This `ActiveRecord` mixin adds support for destroy callbacks without using N delete queries.

## Usage

1. Include the `Concern` in your model
2. Call the `bulk_destroy` method, eg `Model.where(...).bulk_destroy`

### Callbacks
This helper also adds two callbacks to models.
Unlike the builtin callbacks, these callbacks are run at the class level and not the instance level. An `options` Hash is made available to the scope of each callback and contains any `kwargs` passed into `bulk_destroy`.

#### Callbacks
- `:destroy_batch`
  Allows you to add before/after/around logic each time a batch of items is processed and deleted.  
  This callback additionally has `model_class` and `batch` variables made available.

- `:bulk_destroy`
  Allows you to add before/after/around logic to the `bulk_destroy` call of the model. In other words, this runs once per call to `bulk_destroy`, whereas `:destory_batch` may be run multiple times.


## Examples

### Overriding Deletion Logic
The actual deletion logic can be overridden. This allows things like soft deletion as seen in this example.

```ruby
module DestroyWorkflow
  extend ActiveSupport::Concern
  include BatchedDestruction

  class_methods do
    def destroy_bulk_batch(batch, options) # options is the kwargs passed to `bulk_destroy`, along with any modifications made by callbacks
      delete_ids = []
      batch.each do |itm|
        delete_ids << itm.id
        itm.workflow_state = 'deleted'
      end
      where(id: delete_ids).update_all(workflow_state: 'deleted')
    end
  end
end
```

### Callbacks
```ruby
  before_destroy_batch do
    conn_ids = options[:connection_ids] ||= Set.new()
    batch.each do |assn|
      assn_cat_ids = assn.assignment_categories.map(&:category_connection_id)
      conn_ids.merge(assn_cat_ids)
    end
    AssignmentCategory.where(assignment: batch).delete_all()
  end

  after_bulk_destroy do
    conn_ids = options[:connection_ids].to_a()
    course_ids = CategoryConnection.where(id: conn_ids, connectable_type: 'Course').pluck(:connectable_id).uniq
    canvas_course_ids = Course.where(id: course_ids).pluck(:canvas_id)
    canvas_course_ids.each do |course_id|
      BuildRollupsJob.perform_later(course_id, for_connection_ids: conn_ids) if conn_ids.present?
    end
  end
```
