# ParamValidator
A pretty flexible tool for validation parameters, whether from an API, a CSV row, or anything.

## Examples
```ruby
def validate_params(params = nil, &blk)
    errors = ParamValidator.check(params, context: self, &blk)
    raise HttpError, parameter_errors: errors if errors.present?
end

validate_params(params) do
    p :search_term, type: String do |val|
        next unless val.length < 3
        'must be at least 3 characters'
    end
    p :hash_of_options, type: Hash do |val|
        p :nested_param, type: :bool
    end
    p :include_root, type: :bool
end
```
