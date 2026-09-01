# Databricks notebook source
# MAGIC %md
# MAGIC # Day 3 · Notebook 4 — HANDS-ON LAB (Complete the TODOs)
# MAGIC
# MAGIC Same exercise as `local_pyspark/04_lab_exercise_STARTER.py`, now on
# MAGIC your real cluster against the actual ADLS Gen2 Silver data. Run
# MAGIC Notebook 1 first for this `window_date`.
# MAGIC
# MAGIC Don't open Notebook 5 (the reference solution) until you've made a
# MAGIC genuine attempt — compare afterward, not before.

# COMMAND ----------

dbutils.widgets.text("storage_account_name", "", "ADLS Storage Account Name")
dbutils.widgets.text("storage_account_key", "", "ADLS Storage Account Key")
dbutils.widgets.text("window_date", "2026-05-01", "Window Date (yyyy-MM-dd)")

storage_account_name = dbutils.widgets.get("storage_account_name")
storage_account_key = dbutils.widgets.get("storage_account_key")
window_date = dbutils.widgets.get("window_date")

spark.conf.set(
    f"fs.azure.account.key.{storage_account_name}.dfs.core.windows.net",
    storage_account_key,
)
silver_path = f"abfss://silver@{storage_account_name}.dfs.core.windows.net/trades_pyspark/{window_date}/"

# COMMAND ----------

from pyspark.sql import functions as F

silver_df = spark.read.parquet(silver_path)
dim_trader = spark.read.option("header", "true").option("inferSchema", "true") \
    .csv("/FileStore/tables/dim_trader.csv")

# COMMAND ----------

# MAGIC %md
# MAGIC ### TODO 1: Flag large trades for manual review
# MAGIC Add a boolean column `needs_review` that is `True` when
# MAGIC `trade_value > 5000000`.

# COMMAND ----------

flagged_df = silver_df  # <-- replace with your .withColumn("needs_review", ...) call

# COMMAND ----------

# MAGIC %md
# MAGIC ### TODO 2: Broadcast-join trader information
# MAGIC Left-join `flagged_df` to `dim_trader` on `trader_id`, broadcasting
# MAGIC the small dimension table.

# COMMAND ----------

enriched_df = flagged_df  # <-- replace with your .join(F.broadcast(...), ...) call

# COMMAND ----------

# MAGIC %md
# MAGIC ### TODO 3: Aggregate by desk and review flag
# MAGIC Group by `(desk, needs_review)`, computing `total_trade_value`
# MAGIC (sum) and `flagged_trade_count` (count), ordered by
# MAGIC `total_trade_value` descending.

# COMMAND ----------

desk_review_summary = enriched_df  # <-- replace with your .groupBy(...).agg(...) call
display(desk_review_summary)

# COMMAND ----------

# MAGIC %md
# MAGIC ### TODO 4: Which desk has the highest flagged value, as a % of its total?
# MAGIC Write your answer as a markdown cell below, backed by a query.
