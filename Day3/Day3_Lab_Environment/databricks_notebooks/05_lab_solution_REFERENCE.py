# Databricks notebook source
# MAGIC %md
# MAGIC # Day 3 · Notebook 5 — FACILITATOR REFERENCE SOLUTION
# MAGIC
# MAGIC The completed version of Notebook 4. Hold this back until teams
# MAGIC have attempted the lab themselves.

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

# TODO 1 SOLUTION
flagged_df = silver_df.withColumn("needs_review", F.col("trade_value") > 5000000)

# TODO 2 SOLUTION
enriched_df = flagged_df.join(F.broadcast(dim_trader), on="trader_id", how="left")

# TODO 3 SOLUTION
desk_review_summary = (enriched_df
                        .groupBy("desk", "needs_review")
                        .agg(
                            F.sum("trade_value").alias("total_trade_value"),
                            F.count("*").alias("flagged_trade_count"),
                        )
                        .orderBy(F.desc("total_trade_value")))
display(desk_review_summary)

# COMMAND ----------

# TODO 4 SOLUTION
desk_totals = enriched_df.groupBy("desk").agg(F.sum("trade_value").alias("desk_total_value"))
flagged_only = (enriched_df.filter(F.col("needs_review"))
                .groupBy("desk").agg(F.sum("trade_value").alias("flagged_value")))

pct_df = (flagged_only.join(desk_totals, on="desk")
          .withColumn("pct_of_desk_total", F.round(F.col("flagged_value") / F.col("desk_total_value") * 100, 1))
          .orderBy(F.desc("flagged_value")))
display(pct_df)

# COMMAND ----------

# MAGIC %md
# MAGIC **Expected answer (using the full 567-row sample dataset across all
# MAGIC business days):** the Equities desk carries the highest flagged
# MAGIC value, at roughly 79-80% of its total trade value — meaning a large
# MAGIC majority of Equities desk activity by value sits above the review
# MAGIC threshold. Exact numbers will vary slightly by `window_date` since
# MAGIC this is filtered to a single day; run it across multiple days and
# MAGIC compare, exactly like the take-home assignment asks.
