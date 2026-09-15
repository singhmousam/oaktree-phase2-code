-- Bronze / staging for the trader dimension -- same idea, no logic yet.
select
    trader_id,
    trader_name,
    desk,
    region
from {{ ref('dim_trader') }}
