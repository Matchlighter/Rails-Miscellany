# BatchMatcher
Matches a set of rows (eg from a CSV) against Rows in the Database.

## Examples:
```ruby
# Basic Example:
rule_matcher = BatchMatcher.new(
  Rule, # Model to match against
  rows, # Set of Rows to attempt finding matches for
  columns: [
    # [key in Row, key in Model, (Optional Human Name)]
    [:rule_id, :id, 'ID'],
    [:rule_import_id, :import_id, 'Import ID']
  ]
)

# Create a polymorphic matcher that determines the Model types based on a column:
context_matcher = BatchMatcher.new(
  [Account, Course], # Valid polymorphic Models
  rows,
  polymorphic_on: :rule_context,
  columns: [
    [:canvas_context_id, :canvas_id, 'Canvas ID'],
    [:sis_context_id, :sis_id, 'SIS ID']
  ]
)

# An ActiveRecord::Relation can be used instead of a Model Class:
role_matcher = BatchMatcher.new(
  Role.active,
  rows,
  columns: [
    [:canvas_role_id, :canvas_id, 'Canvas Role ID'],
    [:role_label, :label, 'Role Label']
  ]
)
```
