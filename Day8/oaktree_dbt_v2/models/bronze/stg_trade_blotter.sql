-- Bronze / staging: a thin, typed view directly over the raw seed.
-- No business logic here at all -- just casting and renaming if needed.
-- This mirrors the exact "Bronze = exact copy, no transformation" rule
-- from earlier in this program, just expressed as a dbt model instead
-- of a notebook cell or an ADF Copy Activity.

select
    trade_id,
    cast(trade_date as date)              as trade_date,
    security_id,
    trader_id,
    trade_type,
    cast(quantity as decimal(18, 2))      as quantity,
    cast(price as decimal(18, 4))         as price,
    cast(last_modified_ts as timestamp)   as last_modified_ts
from {{ ref('trade_blotter') }}
