# Computed Columns

## Installation
In an Initializer:
```ruby
Miscellany::ComputedColumns.install
```

## Examples
```ruby
define_computed :grade_levels, ->() {
    select "COALESCE(COMPUTED.grade_levels, '{}') AS grade_levels"
    join_condition "COMPUTED.id = users.id"
    query do
        User.joins(:school_data).select('users.id, ARRAY_AGG(user_school_data.grade_level) AS grade_levels').group('users.id').to_sql
    end
}
```

```ruby
records = Model.where( ... ).with_computed(:grade_levels)
records.find_each do |rec|
    rec.grade_levels
end
```
