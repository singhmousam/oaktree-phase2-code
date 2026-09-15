# oaktree_dbt — A dbt Introduction Using This Program's Own Dataset

A fully working, **locally runnable** dbt project — no cloud account, no
Fabric/Databricks access needed. Uses the `duckdb` adapter, so everything
runs against a local file, the same "local practice first" pattern used
throughout this program (DuckDB for Day 1 SQL, local PySpark for Day 3/5).

## Setup

```bash
pip install dbt-duckdb  # or in a virtualenv, drop the flag
cd oaktree_dbt
dbt seed      # loads trade_blotter.csv and dim_trader.csv as raw tables
dbt run       # builds staging views, silver_trades, and both gold tables
dbt test      # runs 8 data quality tests
dbt snapshot  # captures the FIRST version of dim_trader's history (dbt-native SCD2)
```

## What gets built

```
seeds (raw CSV, loaded as-is)
  trade_blotter, dim_trader
        |
models/bronze/  (Bronze — thin typed views, no logic)
  stg_trade_blotter, stg_dim_trader
        |
models/silver/  (Silver — dedupe, filter, compute trade_value)
  silver_trades
        |
models/gold/    (Gold — reporting-ready)
  gold_fact_trades_daily, gold_dim_trader

snapshots/      (dbt-native SCD2 — see below)
  dim_trader_snapshot
```

## Verified results (run it yourself — you'll see the same numbers)

| Step | Result |
|---|---|
| `dbt seed` | 567 rows into `trade_blotter`, 6 rows into `dim_trader` |
| `dbt run` | `silver_trades`: **554 rows** (identical to the PySpark version elsewhere in this program) |
| `dbt run` | `gold_fact_trades_daily`: **290 rows** — BUY total ≈1.61B, SELL total ≈1.72B |
| `dbt test` | **10 pass, 1 intentional failure** — see "The Positive-Value Test" below |
| `dbt snapshot` | Initial capture: 6 rows, all current |

## The Positive-Value Test — One Passes, One Is *Supposed* to Fail

This project includes two versions of "quantity and price must be
positive," placed at two different layers on purpose:

- `models/schema.yml` → `positive_value` test on `silver_trades` —
  **passes**, because the model's own `WHERE` clause already filters
  bad rows. This test exists as a safety net, not because it currently
  catches anything.
- `tests/assert_bronze_trades_positive_quantity_and_price.sql` → a
  singular test on the unfiltered Bronze layer — **fails with 5
  results**, by design. Bronze is a faithful, unfiltered copy of the
  source, and the source genuinely contains 5 bad records (the same
  ones described since Day 1). A failing test here is Bronze doing its
  job correctly, not a broken project.

**Full walkthrough, including exactly why a test can silently pass
when you expect it to fail (and how to fix that), is in
`guides/dbt_Testing_Verification_Troubleshooting.md`.**

## Further Reading

- `guides/dbt_Testing_Verification_Troubleshooting.md` — how to verify
  table content without an external tool, why a test can silently miss
  a data change, and the full positive-value test walkthrough
- `guides/dbt_Project_Reference_and_Fabric_Setup.md` — what every file
  and folder in this project is for, a key-by-key breakdown of
  `dbt_project.yml`, and step-by-step instructions for pointing this
  exact project at a real Microsoft Fabric Warehouse or Lakehouse

## The dbt Snapshot — SCD2 Without Writing Union Logic

This is the payoff for anyone who has already hand-built SCD2 with
PySpark elsewhere in this program: try this experiment yourself.

1. Edit `seeds/dim_trader.csv` to change trader_id 4's desk from
   `Macro` to `Credit` (or make any other change).
2. Run `dbt seed` again, then `dbt snapshot` again.
3. Query the snapshot table:
   ```sql
   SELECT trader_id, trader_name, desk, region, dbt_valid_from, dbt_valid_to
   FROM snapshots.dim_trader_snapshot
   ORDER BY trader_id, dbt_valid_from;
   ```

**Verified result:** trader_id 4 now has TWO rows — the old `Macro`
version with `dbt_valid_to` stamped, and a new `Credit` version with
`dbt_valid_to` still null (current). Total row count: 6 → 10 when all
of the same changes from Assignment 1 are applied (3 changed + 1 new
trader) — the exact same outcome as the hand-built PySpark version,
produced by a 10-line YAML config block instead of a hand-rolled
expire/insert/union pipeline.

**The lesson is not "snapshots are better than what you built by
hand."** It's the opposite: you needed to understand the expire/insert
pattern by hand FIRST to know what a snapshot is actually doing under
the hood, what `strategy: check` versus `strategy: timestamp` changes,
and how to debug it when a snapshot doesn't do what you expected.

## Where This Fits With Everything Else in This Program

| Concept | PySpark / Notebook Version | dbt Version |
|---|---|---|
| Bronze → Silver → Gold | Notebook cells with `.filter()`, `.groupBy()` | SQL `SELECT` statements, one per model |
| Dependency tracking | Manual — you decide what runs before what | `{{ ref('...') }}` — dbt builds the DAG for you |
| Data quality checks | Ad-hoc `.count()` / `assert` statements | Declarative YAML tests, run with one command |
| SCD2 | Hand-written expire/insert/union (Assignments 1 & 2) | A snapshot config block |
| Documentation | Markdown files you maintain separately | `dbt docs generate` — auto-generated from your models and schema.yml |

## Moving to Production: dbt on Fabric

This project targets local DuckDB for practice. In production, the
`dbt-fabric` adapter targets a Fabric Warehouse or Lakehouse SQL
endpoint directly — the `profiles.yml` target changes, but every model,
test, and snapshot file above is unchanged. This is the same
"local practice, then cloud" pattern as every other tool in this
program.
