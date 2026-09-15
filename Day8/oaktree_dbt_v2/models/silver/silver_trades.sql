-- Silver: the exact same three rules you've applied with PySpark and
-- T-SQL elsewhere in this program, now expressed as a dbt model --
-- a plain SQL SELECT statement, version-controlled like any other file.
--
-- Rule 1: de-duplicate, keeping the newest row per trade_id
-- Rule 2: drop bad records (non-positive quantity/price)
-- Rule 3: compute the derived trade_value measure

with deduped as (
    select
        *,
        row_number() over (
            partition by trade_id
            order by last_modified_ts desc
        ) as rn
    from {{ ref('stg_trade_blotter') }}
)

select
    trade_id,
    trade_date,
    security_id,
    trader_id,
    trade_type,
    quantity,
    price,
    round(quantity * price, 2) as trade_value
from deduped
where rn = 1
  and quantity > 0
  and price > 0
