# ComplexQuery
Helper class for building complex/report queries with SQL.
Provides tooling for cleanly converting parameters to SQL WHERE clauses and merging multiple such filters.
More importantly, provides tooling for iterating the data efficiently (using a TEMP table)

## Examples

### Query Definition

```ruby
class StudentDashboardQuery < Miscellany::ComplexQuery
  def build_query
    <<~SQL
      WITH
        teacher_courses_subquery       AS (#{teacher_courses_subquery}),
        students AS (
          SELECT name as course_name FROM teacher_courses_subquery
          WHERE #{join_filters(
            course_status_filter,
            course_filter,
            search_filter
          )}
        )
      SELECT * FROM students
    SQL
  end

  def build_count_query
    # Exercise for the reader ;)
  end

  protected

  def augment_batch(records)
    course_ids = records.map { |r| r['canvas_course_id'] }
    enrollments = Enrollment.where(canvas_course_id: course_ids, base_role_type: %w[TeacherEnrollment TaEnrollment])
    enrollments_by_course = enrollments.group_by(&:canvas_course_id)

    records.each do |r|
      # Augment the Hash
      r['ruby_compute'] = 5
    end
  end

  def teacher_courses_subquery
    if options[:teacher_id].present?
      <<~SQL
        SELECT
          te.canvas_course_id
        FROM enrollments te
        WHERE te.workflow_state IN ('#{Enrollment::ACTIVE_STATUSES.join("', '")}')
          AND te.canvas_user_id = #{options[:teacher_id]}
          AND te.base_role_type = 'TeacherEnrollment'
      SQL
    elsif options[:account_id].present?
      acc = Account.find_by(canvas_id: options[:account_id])
      tree_ids = acc.subtree.pluck(:canvas_id)
      <<~SQL
        SELECT
          courses.canvas_id
        FROM courses
        WHERE courses.canvas_account_id IN (#{tree_ids.join(',')})
      SQL
    end
  end

  def course_status_filter
    if show_all_courses?
      sanitize_sql('courses.workflow_state IN (?)', %w[active completed])
    else
      sanitize_sql('courses.workflow_state = ?', 'active')
    end
  end

  def course_filter
    options[:course_id].present? && sanitize_sql('courses.canvas_id = ?', options[:course_id])
  end

  def search_filter
    options[:search_term].present? && sanitize_sql('users.sortable_name ILIKE ?', "%#{options[:search_term]}%")
  end
end

```

### Usage
```ruby
query = StudentDashboardQuery.new({ course_id: 1 })

query.page(1, page_size: 20) # Returns a page of data, with some pagination metadata - does NOT cache to TEMP table
query.slice(10, 10) # (offset, count) Returns a number of records at the offset - does NOT cache to TEMP table

query.find_each do |record|
  # Each `record` is a Hash
end

query.in_batches(of: 1000) do |batch|
  # Each `batch` is an Array of Hashes
end
```
