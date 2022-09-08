# Arbitrary ActiveRecord Prefetching
A Rails equivalent of [Django `prefetch_related`](https://docs.djangoproject.com/en/4.1/ref/models/querysets/#prefetch-related).

It allows you to create one-off Associations when querying models. Mainly, this allows preloading parameterized associations.

## Setup
Create an Initializer with
```ruby
Miscellany::ArbitraryPrefetch.install
```

Optionally install `goldiloader`.

## Usage
Prefetches take an existing association as a base, and further filter from it.
The created association is made available on model instances just as a normal association is and the added collections leverage Preloading so they will not cause N+1 issues.

`prefetch` is called with key-value pairs, where the key is the name of the created association (and thus how it may be accessed on model instances). The plurality of the key is significant and will be used to determine if the created association is 1:1, or 1:M.
The value may be either a tuple or a Relation.
If a tuple is used, it is expected to be `[:existing_association, OtherModel.where(...)]`. If just a Relation is given, the model's name will be used to find the association to base off of.

## Examples

### Example 1
```ruby
# Based off of a case in learning-teams-lti
enrs = Enrollment.prefetch(
    period_score: Score.for_grading_period(grading_period),
    period_work_habits_score: WorkHabitsScore.for_grading_period(grading_period),
)

enrs.find_each do |e|
    puts e.period_score # => <Score ...>
    puts e.period_work_habits_score # => <WorkHabitsScore ...>
end
```

A normal Association could not accomplish this because there is no way to pass parameters (`grading_period`) when using `preload`/`includes`.
Without using a `prefetch`, this would either be a N+1, or we'd need to come up with another solution to preloading and looking-up preloaded items.

### Example 2
```ruby
# Based off of a case in canvas-group-enrollment

active_rule_enrollments_base = RuleEnrollment.kept
    .distinct(:rule_id)
    .joins(:rule)
    .left_outer_joins(:rule_group)
    .where(
        rule_enrollments: {
            rules: { discarded_at: nil },
            rule_groups: { discarded_at: nil }
        }
    )

users = User.where(...).prefetch(
    course_enrollments: Enrollment.where(
        canvas_course_id: course.canvas_id,
        status: Enrollment::VALID_ENROLLMENTS
    ).prefetch(
        active_rule_enrollments: active_rule_enrollments_base
    )
)

users.find_each do |u|
    u.course_enrollments.each do |enr|
        puts enr.active_rule_enrollments # => <ActiveRecord::Relation RuleEnrollment [ ... ]>
    end
end
```

As can be seen, nesting is also supported.

