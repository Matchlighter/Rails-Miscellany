# BatchingCsvProcessor

## Examples:

```ruby
class RuleImportProcessor < BatchingCsvProcessor
  def run
    process_in_batches do |batch|
      # If using BatchMatchers, create them to use when looking for existing Items
      # (BatchMatchers work per-batch, so you'll need to create new ones for each batch)
      @rule_matcher = BatchMatcher.new(...)
      @context_matcher = BatchMatcher.new(...)

      # Map the batch of rows to a batch of Models
      rules_batch = batch.map { |r| build_model_from_row(r) }.reject { |r| r.nil? || !r.changed? }
      # The above logic is wrapped in batch_rows_to_models:
      rules_batch = batch_rows_to_models(batch)

      # Use your logic (eg ActiveRecord Import) to save the batch
      Rule.import(rules_batch)
    end
  end

  # Logic to find a matching Model for the given Row.
  # It is recommended to use BatchMatcher (as this example is doing).
  def find_or_init(row)
    @rule_matcher.get_for_row(row) || Rule.new
  end

  # Logic to assign values from row -> model
  def apply_row_to_model(row, rule)
    # You can use a secondary BatchMatcher:
    rule.context = @context_matcher.get_for_row!(row)
    # Any other logic to assign values from `row` to `rule`
    rule.assign_attributes(...)
  end

  # Logic to handling logging of errors
  def log_line_error(message, line_number, error: nil)
    # Your logic to log the error for the User.
    # If error is not a RowError or a ActiveRecord::NotFound, message is "An Internal Error Occurred"
    uploader_job.errors << [message, line_number]

    # BatchingCsvProcessor provides RowError to indicate some-sort of User error.
    # It may also raise an ActiveRecord::NotFound if a matching model could not be found.
    Raven.capture(error) unless !error || error.is_a?(RowError) || error.is_a?(ActiveRecord::NotFound)
  end

  # Optionally provide logic for validating each Row
  def get_row_errors(row)
    ParamValidator.check(row, context: self) do
      p :rule_context, present: true, one_of: %w[Account Course]
      parameters [:canvas_role_id, :role_label], one_present: true
    end
  end

  # Optionally provide custom logic for matching headers.
  # This is more intended to be used externally to determine if this processor can process a given file.
  def self.headers_match?(headers)
  end
end

RuleImportProcessor.new(csv_file_path, file_name).run
```
