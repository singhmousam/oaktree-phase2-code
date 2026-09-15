{#
    A GENERIC test (as opposed to the singular test in tests/) -- this is a
    reusable macro you can apply to ANY column, in ANY model, by name, from
    schema.yml. dbt ships this pattern as `dbt_utils.expression_is_true` in
    the popular dbt_utils package; this is a small, dependency-free version
    of the same idea, so this project doesn't require running `dbt deps`
    just to demonstrate the concept.

    Usage in schema.yml:
        - name: quantity
          tests:
            - positive_value
#}

{% test positive_value(model, column_name) %}

select *
from {{ model }}
where {{ column_name }} <= 0

{% endtest %}
