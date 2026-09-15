{#
    THIS IS THE PUNCHLINE OF THE WHOLE SCD2 THREAD IN THIS PROGRAM.

    You have hand-built SCD Type 2 twice now: once for dim_trader
    (Assignment 1) and once for trade facts themselves (Assignment 2) --
    each time writing your own expire-old-row / insert-new-row / union
    logic in PySpark.

    dbt has this pattern built in, called a SNAPSHOT. Point it at a
    source, tell it which column(s) identify a "version changed", and
    dbt automatically:
      - adds dbt_valid_from / dbt_valid_to columns (exactly like your
        valid_from / valid_to)
      - adds dbt_scd_id (a surrogate key per version, like trader_key)
      - never deletes a row, only closes it out when something changes

    You still need to UNDERSTAND the pattern by hand first -- which is
    exactly why this program built it manually before showing you the
    automated version. Skipping straight to snapshots without
    understanding what they do underneath is how teams end up unable to
    debug them when something looks wrong.
#}

{% snapshot dim_trader_snapshot %}

{{
    config(
      target_schema='snapshots',
      unique_key='trader_id',
      strategy='check',
      check_cols=['desk', 'region', 'trader_name'],
    )
}}

select
    trader_id,
    trader_name,
    desk,
    region
from {{ ref('stg_dim_trader') }}

{% endsnapshot %}
