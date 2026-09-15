-- Gold dimension: a clean, business-facing view of the trader reference
-- data. (The SCD2-aware version of this table is handled separately by
-- a dbt SNAPSHOT -- see snapshots/dim_trader_snapshot.sql and the
-- accompanying deck section on why dbt treats history as a snapshot
-- concept rather than something you hand-build inside a model.)

select
    trader_id,
    trader_name,
    desk,
    region
from {{ ref('stg_dim_trader') }}
