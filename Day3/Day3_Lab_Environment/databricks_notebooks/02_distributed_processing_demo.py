# Databricks notebook source
# MAGIC %md
# MAGIC # Day 3 · Notebook 2 — Distributed Processing Concepts (Real Cluster)
# MAGIC
# MAGIC Same demo as `local_pyspark/02_distributed_processing_demo.py`, run
# MAGIC against your actual Databricks cluster so partition counts and the
# MAGIC physical plan reflect real, multi-node behavior instead of a
# MAGIC single laptop's `local[4]`.
# MAGIC
# MAGIC Run Notebook 1 first so the Silver Parquet output exists.

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

# COMMAND ----------

# MAGIC %md ## 1. Partitions — how many does the cluster actually give you?

# COMMAND ----------

print(f"Cluster default parallelism: {spark.sparkContext.defaultParallelism}")
print(f"Partitions after reading Parquet: {silver_df.rdd.getNumPartitions()}")

repartitioned = silver_df.repartition(8, "security_id")
print(f"After repartition(8, 'security_id'): {repartitioned.rdd.getNumPartitions()}")

# COMMAND ----------

# MAGIC %md ## 2. Shuffle — inspect the physical plan in the Spark UI
# MAGIC
# MAGIC Run the cell below, then open the **Spark UI** tab on this cluster
# MAGIC and find this job under **SQL / DataFrame**. Look for the
# MAGIC `Exchange` node in the query plan diagram — that's the shuffle,
# MAGIC and on a real cluster you can click into it to see exactly how
# MAGIC much data moved between which executors.

# COMMAND ----------

daily_totals = (silver_df.groupBy("trade_type")
                 .agg(F.sum("trade_value").alias("total_value"), F.count("*").alias("trade_count")))
daily_totals.explain()
display(daily_totals)

# COMMAND ----------

# MAGIC %md ## 3. Broadcast join — read the dimension CSVs from DBFS
# MAGIC
# MAGIC Upload `dim_security.csv` and `dim_trader.csv` via **Data > Add
# MAGIC Data > Upload File** into DBFS first (see the Portal step-by-step
# MAGIC guide for the click path), then adjust the paths below if needed.

# COMMAND ----------

dim_security = spark.read.option("header", "true").option("inferSchema", "true") \
    .csv("/FileStore/tables/dim_security.csv")
dim_trader = spark.read.option("header", "true").option("inferSchema", "true") \
    .csv("/FileStore/tables/dim_trader.csv")

enriched_df = (silver_df
               .join(F.broadcast(dim_security), on="security_id", how="left")
               .join(F.broadcast(dim_trader), on="trader_id", how="left"))

display(enriched_df.select("trade_id", "ticker", "asset_class", "trader_name", "desk", "trade_value"))

# COMMAND ----------

# MAGIC %md ## 4. Caching — reuse enriched_df across two aggregations

# COMMAND ----------

enriched_df.cache()
enriched_df.count()  # materialize the cache

display(enriched_df.groupBy("desk").agg(F.sum("trade_value").alias("total_value")).orderBy(F.desc("total_value")))
display(enriched_df.groupBy("asset_class").agg(F.sum("trade_value").alias("total_value")).orderBy(F.desc("total_value")))
