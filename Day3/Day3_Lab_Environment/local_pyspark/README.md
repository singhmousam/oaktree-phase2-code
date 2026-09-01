# Day 3 — Local PySpark Practice Environment

Run these on your own laptop with **no cluster, no Azure account, and no
Databricks access required** — just Python 3.10+ and `pip install pyspark`.
This is the same PySpark DataFrame API you'll use on a real Databricks
cluster this afternoon; only the source/sink paths differ (local files here,
`abfss://...` paths there — see `databricks_notebooks/` for the cluster
versions).

## Setup

```bash
pip install pyspark --break-system-packages   # or in a virtualenv, drop the flag
cd local_pyspark
```

## Run order

```bash
python3 01_bronze_to_silver.py              # Bronze -> Silver (567 -> 554 rows)
python3 02_distributed_processing_demo.py   # partitions, shuffle, broadcast join, caching
python3 03_gold_aggregation.py              # Silver -> Gold (120 grouped rows)
```

Then attempt the lab exercise yourself:

```bash
python3 04_lab_exercise_STARTER.py          # has 4 TODOs — complete them
python3 05_lab_solution_REFERENCE.py        # facilitator reference — don't peek early!
```

## Verified results (so you know what "correct" looks like)

| Script | Output |
|---|---|
| `01_bronze_to_silver.py` | Bronze: 567 rows → Silver: 554 rows (13 removed: 8 duplicates + 5 bad records) — **matches Day 2's SQL-based Silver exactly** |
| `02_distributed_processing_demo.py` | Shows a real Spark physical plan with an `Exchange` (shuffle) step; broadcast join produces 554 enriched rows; totals by desk: Equities ≈1.66B, Credit ≈1.08B, Macro ≈0.58B |
| `03_gold_aggregation.py` | 120 Gold rows (grouped by date × asset_class × trade_type); total May 2026 trade value ≈ 2.19B |
| `05_lab_solution_REFERENCE.py` | Equities desk has the highest flagged (>5M notional) trade value: ≈1.32B, or 79.5% of that desk's total |

## Why local practice exists at all

Not everyone has Databricks cluster access provisioned before class starts,
and clusters take a few minutes to spin up. Practicing the exact same
DataFrame transformations locally first means:

1. You can debug your own logic errors instantly, without waiting on cluster
   start-up time or fighting unrelated cloud connectivity issues.
2. When you do move to the real Databricks cluster (see
   `databricks_notebooks/`), you already know the transformations work —
   you're only adapting I/O paths, not debugging logic from scratch.

This mirrors exactly how the Day 1 SQL demo used DuckDB before Day 2 moved
to a real Azure SQL Database — same principle, one module later.
