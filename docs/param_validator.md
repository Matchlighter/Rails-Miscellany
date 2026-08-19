# ParamValidator
A pretty flexible tool for validation parameters, whether from an API, a CSV row, or anything.

## Examples
```ruby
def validate_params(params = nil, &blk)
    errors = ParamValidator.check(params, context: self, &blk)
    # Build the error explicitly. `raise HttpError, parameter_errors: errors` would
    # pass the Hash as the message instead of populating `extra`, so the payload
    # would reach the client as a stringified Hash rather than its own JSON key.
    raise HttpError.new('invalid parameters', status: 422, parameter_errors: errors.serialize) if errors.present?
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

### Types

`type:` accepts a class, a Symbol, a Proc, or an Array of any of those. It may also
be passed positionally, so `p :count, Integer` and `p :count, type: Integer` are
equivalent.

Supported: `Integer`, `Float`, `Numeric`, `String`, `Array`, `Hash`, `BigDecimal`,
`Date`, `DateTime`, `Time`, `:bool`/`:boolean`, any `ActiveRecord::Base` subclass
(looked up via `find_by!`), and any Proc. A value that is already an instance of the
requested type passes through untouched.

A `type:` with no coercion rule raises `ParamValidator::UnsupportedTypeError`, since
that is a mistake in the validator rather than bad input.
