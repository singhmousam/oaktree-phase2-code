# Databricks notebook source
# MAGIC %md
# MAGIC # Day 3 · Notebook 3 — Gold Aggregation (Real Cluster)
# MAGIC
# MAGIC Builds `gold_trades_daily` in ADLS Gen2, in the exact star-schema
# MAGIC shape from Day 1 — ready for Day 6's Power BI semantic model to
# MAGIC read via Direct Lake mode.

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
gold_path = f"abfss://silver@{storage_account_name}.dfs.core.windows.net/../gold/trades_daily/{window_date}/"

# COMMAND ----------

from pyspark.sql import functions as F

silver_df = spark.read.parquet(silver_path)
dim_security = spark.read.option("header", "true").option("inferSchema", "true") \
    .csv("/FileStore/tables/dim_security.csv")

gold_df = (silver_df
           .join(F.broadcast(dim_security), on="security_id", how="left")
           .groupBy("trade_date", "asset_class", "trade_type")
           .agg(
               F.sum("trade_value").alias("total_trade_value"),
               F.count("*").alias("trade_count"),
               F.round(F.avg("price"), 2).alias("avg_price"),
           )
           .orderBy(F.desc("total_trade_value")))

print(f"GOLD row count for {window_date}: {gold_df.count()}")
display(gold_df)

# COMMAND ----------

gold_df.write.mode("overwrite").parquet(gold_path)
print(f"Gold written to {gold_path}")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Bonus: register as a table for SQL access
# MAGIC
# MAGIC This makes `gold_trades_daily` queryable with plain SQL from any
# MAGIC notebook or the Databricks SQL editor — a preview of the semantic
# MAGIC layer thinking from Day 6.

# COMMAND ----------

gold_df.write.mode("overwrite").saveAsTable("gold_trades_daily")

# COMMAND ----------

# MAGIC %sql
# MAGIC SELECT asset_class, trade_type, SUM(total_trade_value) AS grand_total
# MAGIC FROM gold_trades_daily
# MAGIC GROUP BY asset_class, trade_type
# MAGIC ORDER BY grand_total DESC
