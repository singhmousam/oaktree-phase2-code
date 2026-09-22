# Fabric notebook source
# METADATA ********************

# MARKDOWN ********************
# # Introducing Microsoft Fabric — A Simple End-to-End ETL
#
# This notebook is intentionally kept simple. It does ONE thing end to end:
# takes the OakTree trade blotter (the same sample file used throughout this
# program) through **Bronze → Silver → Gold**, and at the Gold layer, keeps
# a **full history** of trader/desk changes using **SCD Type 2**.
#
# You will run this exactly as-is first. Then, in the take-home exercise,
# you'll change one thing (a new update snapshot) and re-run it to see the
# history grow.
#
# **What you need before running this:**
# - A Fabric workspace with a Lakehouse attached to this notebook
# - Three files uploaded to `Files/bronze/` in that Lakehouse:
#   `trade_blotter.csv`, `dim_trader.csv`, `dim_trader_snapshot_20260601.csv`
# - (See the companion "Spin Up the Environment" guide for exact steps)

# CELL ********************

# MARKDOWN ********************
# ## Step 0 — Settings
# Two dates control this run. Change `SNAPSHOT_DATE` when you re-run this
# notebook against a NEW update file later (e.g., the take-home exercise).

# CELL ********************

from pyspark.sql import functions as F
from pyspark.sql.window import Window

INITIAL_LOAD_DATE = "2026-01-01"   # the date the dimension was first loaded
SNAPSHOT_DATE = "2026-06-01"       # the date THIS update snapshot arrived
FAR_FUTURE_DATE = "9999-12-31"     # a sentinel meaning "still true today"

print("Settings loaded. Ready to build Bronze -> Silver -> Gold.")

# CELL ********************

# MARKDOWN ********************
# ## Step 1 — Bronze: land the raw files, exactly as they arrived
#
# No cleaning, no filtering, no renaming. Bronze's only job is to be a
# faithful, permanent copy of the source — if anything ever looks wrong
# downstream, this is where you come to check "what did the source
# actually send us?"

# CELL ********************

bronze_trades = (spark.read
                  .option("header", "true")
                  .option("inferSchema", "true")
                  .csv("Files/bronze/trade_blotter.csv"))

bronze_dim_trader = (spark.read
                      .option("header", "true")
                      .option("inferSchema", "true")
                      .csv("Files/bronze/dim_trader.csv"))

print(f"Bronze trades: {bronze_trades.count()} rows")
print(f"Bronze dim_trader: {bronze_dim_trader.count()} rows")
display(bronze_trades.limit(5))

# CELL ********************

# MARKDOWN ********************
# ## Step 2 — Silver: clean the trades
#
# Three rules, applied in order:
# 1. **De-duplicate** — if the same `trade_id` appears more than once
#    (a retried load), keep only the newest version
# 2. **Drop bad records** — a trade with zero or negative quantity/price
#    is a data-entry error, not a real trade
# 3. **Compute `trade_value`** — a derived column every downstream step needs

# CELL ********************

# Rule 1: keep only the newest row per trade_id
dedupe_window = Window.partitionBy("trade_id").orderBy(F.col("last_modified_ts").desc())

silver_trades = (bronze_trades
                  .withColumn("row_number", F.row_number().over(dedupe_window))
                  .filter(F.col("row_number") == 1)
                  .drop("row_number"))

# Rule 2: drop bad records
silver_trades = silver_trades.filter(F.col("quantity") > 0).filter(F.col("price") > 0)

# Rule 3: compute the derived measure
silver_trades = silver_trades.withColumn(
    "trade_value", F.round(F.col("quantity") * F.col("price"), 2)
)

print(f"Bronze had {bronze_trades.count()} rows -> Silver has {silver_trades.count()} rows")

silver_trades.write.mode("overwrite").format("delta").saveAsTable("silver_trades")
print("Saved as Delta table: silver_trades")

bronze_dim_trader.write.mode("overwrite").format("delta").saveAsTable("bronze_dim_trader")
print("Saved as Delta table: bronze_dim_trader")
# CELL ********************

# MARKDOWN ********************
# ## Step 3 — Gold (Fact): the aggregated table business users query
#
# One row per (date, trader, trade type) — small, fast, and exactly the
# shape a Power BI report wants. This table can ALWAYS be safely rebuilt
# from Silver — it holds no information Silver doesn't already have.

# CELL ********************

gold_fact_trades_daily = (silver_trades
                           .groupBy("trade_date", "trader_id", "trade_type")
                           .agg(
                               F.sum("trade_value").alias("total_trade_value"),
                               F.count("*").alias("trade_count"),
                           ))

print(f"Gold fact_trades_daily: {gold_fact_trades_daily.count()} rows")

gold_fact_trades_daily.write.mode("overwrite").format("delta").saveAsTable("gold_fact_trades_daily")
print("Saved as Delta table: gold_fact_trades_daily")

# CELL ********************

# MARKDOWN ********************
# ## Step 4 — Gold (Dimension): SCD Type 2 for dim_trader
#
# This table is DIFFERENT from the fact table above — it cannot simply be
# rebuilt from scratch every run, because it needs to REMEMBER history.
#
# The business scenario: traders occasionally change desks. If a trade
# happened while a trader was on the Macro desk, and they've since moved
# to Credit, a report about that trade must still say "Macro" — not
# silently change the answer because the dimension was overwritten.
#
# The pattern, in four steps:
# 1. Load (or create) the dimension table with `valid_from`, `valid_to`,
#    and `is_current` columns
# 2. Compare each incoming row to the trader's CURRENT row — did anything
#    change?
# 3. For anyone who changed: **close out** their old row (stamp `valid_to`,
#    flip `is_current` to False) — never delete it
# 4. For anyone who changed (or is brand new): **open a new current row**

# CELL ********************

# Step 4.1 — load the existing Gold dimension, or create it on the very first run
if spark.catalog.tableExists("gold_dim_trader_scd2"):
    gold_dim_trader = spark.table("gold_dim_trader_scd2")
else:
    gold_dim_trader = (bronze_dim_trader
                        .withColumn("valid_from", F.lit(INITIAL_LOAD_DATE).cast("date"))
                        .withColumn("valid_to", F.lit(FAR_FUTURE_DATE).cast("date"))
                        .withColumn("is_current", F.lit(True)))

print("Gold dim_trader BEFORE today's update:")
display(gold_dim_trader.orderBy("trader_id"))

# CELL ********************

# Step 4.2 — load today's incoming snapshot and find who changed
incoming_snapshot = (spark.read
                      .option("header", "true")
                      .option("inferSchema", "true")
                      .csv(f"Files/bronze/dim_trader_snapshot_{SNAPSHOT_DATE.replace('-', '')}.csv")
                      .drop("snapshot_date"))

current_rows = gold_dim_trader.filter(F.col("is_current") == True)  # noqa: E712

comparison = (current_rows.alias("old")
              .join(incoming_snapshot.alias("new"), on="trader_id", how="outer")
              .filter(
                  F.col("old.trader_id").isNull() |             # brand new trader
                  (F.col("old.desk") != F.col("new.desk")) |     # desk changed
                  (F.col("old.region") != F.col("new.region"))   # region changed
              ))

changed_trader_ids = [row.trader_id for row in
                      comparison.select(F.coalesce("old.trader_id", "new.trader_id").alias("trader_id"))
                      .collect()]

print(f"Traders with a change today: {sorted(changed_trader_ids)}")

# CELL ********************

# Step 4.3 — close out the old row for everyone who changed
closed_out_rows = (current_rows
                    .filter(F.col("trader_id").isin(changed_trader_ids))
                    .withColumn("valid_to", F.date_sub(F.lit(SNAPSHOT_DATE).cast("date"), 1))
                    .withColumn("is_current", F.lit(False)))

# Everyone else keeps their current row exactly as it was
untouched_rows = current_rows.filter(~F.col("trader_id").isin(changed_trader_ids))

# Anything already historical from an EARLIER update stays as-is
already_historical_rows = gold_dim_trader.filter(F.col("is_current") == False)  # noqa: E712

# Step 4.4 — open a new current row for everyone who changed (or is new)
new_current_rows = (incoming_snapshot
                     .filter(F.col("trader_id").isin(changed_trader_ids))
                     .withColumn("valid_from", F.lit(SNAPSHOT_DATE).cast("date"))
                     .withColumn("valid_to", F.lit(FAR_FUTURE_DATE).cast("date"))
                     .withColumn("is_current", F.lit(True)))

# Put it all back together into the final table
gold_dim_trader_scd2 = (already_historical_rows
                         .unionByName(untouched_rows)
                         .unionByName(closed_out_rows)
                         .unionByName(new_current_rows))

gold_dim_trader_scd2.write.mode("overwrite").format("delta").saveAsTable("gold_dim_trader_scd2")

print("Gold dim_trader AFTER today's update:")
display(gold_dim_trader_scd2.orderBy("trader_id", "valid_from"))
print(f"\nRow count: {gold_dim_trader_scd2.count()} (started with {bronze_dim_trader.count()})")

# CELL ********************

# MARKDOWN ********************
# ## Step 5 — Prove it: a point-in-time question
#
# "What desk was trader_id 4 on, back in March — BEFORE this update?"
# versus "What desk are they on today?" The SAME table answers both,
# correctly, just by changing one date.

# CELL ********************

# MAGIC %%sql
# MAGIC SELECT trader_id, trader_name, desk, region, valid_from, valid_to, is_current
# MAGIC FROM gold_dim_trader_scd2
# MAGIC WHERE trader_id = 4
# MAGIC ORDER BY valid_from

# CELL ********************

# MARKDOWN ********************
# ## Done
#
# You now have three Gold-ready Delta tables in this Lakehouse:
# - `silver_trades` — cleaned, still fact-grain
# - `gold_fact_trades_daily` — aggregated, rebuildable any time
# - `gold_dim_trader_scd2` — history-aware, NEVER simply overwritten
#
# **Next:** see "Turning This Into a Production Pipeline" in the deck for
# how this exact notebook gets scheduled inside a Fabric Data Pipeline.
