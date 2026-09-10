# Fabric notebook source
# METADATA ********************

# MARKDOWN ********************
# # Assignment 2 — SCD2 on Trade Data Itself (Not Just a Dimension)
#
# **The scenario:** so far, SCD2 has only touched `dim_trader` — a reference
# table. But OakTree's middle office runs a trade reconciliation process
# roughly two to three weeks after the trade date, comparing internal
# records against custodian confirmations. Sometimes this catches a
# genuine booking error: a fat-fingered quantity, a stale price used at
# execution, a partial-fill mismatch.
#
# When a correction is confirmed, the trade record must be updated — but
# whatever number was originally reported to compliance, risk, or a
# trading desk P&L report on the ORIGINAL date must still be reproducible.
# **You cannot simply overwrite the trade.**
#
# This is the exact same SCD2 pattern you've already used on `dim_trader`
# — applied to a fact table instead of a dimension. That's the whole
# assignment: prove to yourself the pattern generalizes.
#
# **Prerequisite:** run `fabric_intro_etl_notebook.py` first (or at least
# have `silver_trades` already built in your Lakehouse).
#
# **Before running this:** upload `trade_amendments_20260520.csv` into
# `Files/bronze/` in your Lakehouse.

# CELL ********************

from pyspark.sql import functions as F

INITIAL_LOAD_DATE = "2026-01-01"
FAR_FUTURE_DATE = "9999-12-31"
AMENDMENT_BATCH_DATE = "2026-05-20"   # the date middle office confirmed these corrections

print("Settings loaded.")

# CELL ********************

# MARKDOWN ********************
# ## Step 1 — Build the initial Gold SCD2 fact table (first run only)
#
# Just like `gold_dim_trader_scd2`, every trade starts as ONE current
# version. This code is provided — read it, but you don't need to change
# anything here.

# CELL ********************

silver_trades = spark.table("silver_trades")

if spark.catalog.tableExists("gold_fact_trades_scd2"):
    gold_fact_trades = spark.table("gold_fact_trades_scd2")
else:
    gold_fact_trades = (silver_trades
                         .withColumn("valid_from", F.lit(INITIAL_LOAD_DATE).cast("date"))
                         .withColumn("valid_to", F.lit(FAR_FUTURE_DATE).cast("date"))
                         .withColumn("is_current", F.lit(True))
                         .withColumn("amendment_reason", F.lit(None).cast("string"))
                         .select("trade_id", "trade_date", "security_id", "trader_id", "trade_type",
                                 "quantity", "price", "trade_value", "valid_from", "valid_to",
                                 "is_current", "amendment_reason"))

print(f"Gold fact_trades_scd2: {gold_fact_trades.count()} rows")

# Look at the 5 trades that are about to be corrected, BEFORE the correction
trades_to_watch = [100015, 100019, 100035, 100038, 100045]
print("\nBEFORE this assignment's correction:")
display(gold_fact_trades.filter(F.col("trade_id").isin(trades_to_watch))
        .select("trade_id", "quantity", "price", "trade_value", "is_current"))

# CELL ********************

# MARKDOWN ********************
# ## Step 2 — Load the amendment batch
#
# This file represents what middle office sent over: the corrected
# quantity/price for 5 trades, with a reason and the date the correction
# was confirmed.

# CELL ********************

amendments = (spark.read
              .option("header", "true")
              .option("inferSchema", "true")
              .csv("Files/bronze/trade_amendments_20260520.csv"))

display(amendments)

# CELL ********************

# MARKDOWN ********************
# ## TODO 1 — Identify which trades are being amended
# You already know this pattern from `dim_trader`. Get the list of
# `trade_id` values present in `amendments`.

# CELL ********************

amended_trade_ids = []  # <-- TODO: replace with the list of trade_id values in `amendments`

print(f"Trades being amended: {sorted(amended_trade_ids)}")

# CELL ********************

# MARKDOWN ********************
# ## TODO 2 — Close out the old (as-originally-booked) version
# For every trade being amended, take its CURRENT row (`is_current = True`)
# and expire it: `valid_to` = the day before `AMENDMENT_BATCH_DATE`,
# `is_current` = False.
#
# **Think before you code:** what should happen to trades NOT in this
# amendment batch? (Hint: they need to stay in the final table, completely
# untouched — you'll need a second DataFrame for them.)

# CELL ********************

current_rows = gold_fact_trades.filter(F.col("is_current") == True)  # noqa: E712

expired_rows = current_rows  # <-- TODO: filter to amended_trade_ids, then expire (see hint above)

untouched_rows = current_rows  # <-- TODO: filter to trades NOT in amended_trade_ids

already_historical_rows = gold_fact_trades.filter(F.col("is_current") == False)  # noqa: E712

# CELL ********************

# MARKDOWN ********************
# ## TODO 3 — Open the new (corrected) version
# Build a new DataFrame from `amendments` with the corrected `quantity`
# and `price`, a freshly computed `trade_value`, `valid_from` =
# `AMENDMENT_BATCH_DATE`, `valid_to` = far future, `is_current` = True.
# Make sure its columns line up with the other three DataFrames above —
# check `gold_fact_trades.columns` if you're not sure what's expected.

# CELL ********************

new_versions = amendments  # <-- TODO: build the corrected current-version rows

# CELL ********************

# MARKDOWN ********************
# ## TODO 4 — Put it all together
# Union all four pieces into the final table and save it.

# CELL ********************

gold_fact_trades_scd2_final = gold_fact_trades  # <-- TODO: unionByName(...) all four DataFrames

gold_fact_trades_scd2_final.write.mode("overwrite").format("delta").saveAsTable("gold_fact_trades_scd2")

print(f"Total rows: {gold_fact_trades_scd2_final.count()}")
print("\nAFTER correction — full history for the 5 amended trades:")
display(gold_fact_trades_scd2_final.filter(F.col("trade_id").isin(trades_to_watch))
        .orderBy("trade_id", "valid_from"))

# CELL ********************

# MARKDOWN ********************
# ## Step 5 — Prove it (same pattern as the dim_trader assignment)
#
# Run the SQL cell below and answer in a markdown cell underneath it:
# **If a P&L report had been generated on 2026-05-10 for trade_id 100015,
# what quantity would it have shown? What does today's corrected book
# show instead? Is the difference material — and why might a 10x quantity
# error like this matter more than a small price correction?**

# CELL ********************

# MAGIC %%sql
# MAGIC SELECT trade_id, quantity, price, trade_value, valid_from, valid_to, is_current
# MAGIC FROM gold_fact_trades_scd2
# MAGIC WHERE trade_id = 100015
# MAGIC ORDER BY valid_from

# CELL ********************

# MARKDOWN ********************
# ## Your answer here:
#
#
