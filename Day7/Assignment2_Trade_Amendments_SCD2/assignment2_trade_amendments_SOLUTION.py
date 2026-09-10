# Fabric notebook source
# METADATA ********************

# MARKDOWN ********************
# # Assignment 2 — FACILITATOR / REFERENCE SOLUTION
# Hold this back until participants have made a genuine attempt at
# `assignment2_trade_amendments_STARTER.py`.

# CELL ********************

from pyspark.sql import functions as F

INITIAL_LOAD_DATE = "2026-01-01"
FAR_FUTURE_DATE = "9999-12-31"
AMENDMENT_BATCH_DATE = "2026-05-20"

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

amendments = (spark.read.option("header", "true").option("inferSchema", "true")
              .csv("Files/bronze/trade_amendments_20260520.csv"))

# TODO 1 SOLUTION
amended_trade_ids = [row.trade_id for row in amendments.select("trade_id").collect()]
print(f"Trades being amended: {sorted(amended_trade_ids)}")

# TODO 2 SOLUTION
current_rows = gold_fact_trades.filter(F.col("is_current") == True)  # noqa: E712

expired_rows = (current_rows
                 .filter(F.col("trade_id").isin(amended_trade_ids))
                 .withColumn("valid_to", F.date_sub(F.lit(AMENDMENT_BATCH_DATE).cast("date"), 1))
                 .withColumn("is_current", F.lit(False)))

untouched_rows = current_rows.filter(~F.col("trade_id").isin(amended_trade_ids))
already_historical_rows = gold_fact_trades.filter(F.col("is_current") == False)  # noqa: E712

# TODO 3 SOLUTION
new_versions = (amendments
                 .withColumn("trade_value", F.round(F.col("quantity") * F.col("price"), 2))
                 .withColumn("valid_from", F.lit(AMENDMENT_BATCH_DATE).cast("date"))
                 .withColumn("valid_to", F.lit(FAR_FUTURE_DATE).cast("date"))
                 .withColumn("is_current", F.lit(True))
                 .select("trade_id", "trade_date", "security_id", "trader_id", "trade_type",
                         "quantity", "price", "trade_value", "valid_from", "valid_to",
                         "is_current", "amendment_reason"))

# TODO 4 SOLUTION
gold_fact_trades_scd2_final = (already_historical_rows
                                .unionByName(untouched_rows)
                                .unionByName(expired_rows)
                                .unionByName(new_versions))

gold_fact_trades_scd2_final.write.mode("overwrite").format("delta").saveAsTable("gold_fact_trades_scd2")

print(f"Total rows: {gold_fact_trades_scd2_final.count()} "
      f"(started with {silver_trades.count()}, {len(amended_trade_ids)} trades amended)")

trades_to_watch = [100015, 100019, 100035, 100038, 100045]
print("\nAFTER correction — full history for the 5 amended trades:")
display(gold_fact_trades_scd2_final.filter(F.col("trade_id").isin(trades_to_watch))
        .orderBy("trade_id", "valid_from"))

# CELL ********************

# MAGIC %%sql
# MAGIC SELECT trade_id, quantity, price, trade_value, valid_from, valid_to, is_current
# MAGIC FROM gold_fact_trades_scd2
# MAGIC WHERE trade_id = 100015
# MAGIC ORDER BY valid_from

# CELL ********************

# MARKDOWN ********************
# ## Reference answer
#
# **VERIFIED RESULT:**
# - A report run on 2026-05-10 for trade_id 100015 would show:
#   **quantity = 900, trade_value = 811,989** (the original, since-corrected booking)
# - Today's corrected book shows:
#   **quantity = 90, trade_value = 81,198.90**
#
# The difference is a full order of magnitude — a classic "extra zero"
# fat-finger error. This is exactly why the assignment picked this trade
# to highlight: a price correction of a few cents rarely changes a
# risk conclusion, but a 10x quantity error absolutely can — it could
# flip a position from within-limit to a limit breach, or make a
# desk's daily P&L look wrong by a large margin. SCD2 doesn't just
# preserve history for its own sake; it preserves the ability to
# explain, after the fact, exactly how wrong a number used to be and
# when it got fixed.
#
# **Total rows: 554 → 559** (5 trades amended, each producing one
# historical + one current row — no trade was deleted, no history was lost).
