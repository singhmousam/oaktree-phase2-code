-- Gold: one row per (date, trader, trade_type), report-ready.
-- Holds no information silver_trades doesn't already have -- if this
-- table were dropped right now, `dbt run` alone rebuilds it perfectly.

select
    trade_date,
    trader_id,
    trade_type,
    sum(trade_value) as total_trade_value,
    count(*)         as trade_count
from {{ ref('silver_trades') }}
group by trade_date, trader_id, trade_type
