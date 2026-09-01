# Databricks notebook source
# MAGIC %md
# MAGIC # Day 3 · Notebook 1 — Bronze to Silver (Real Cluster Version)
# MAGIC
# MAGIC This is the cluster version of `local_pyspark/01_bronze_to_silver.py`.
# MAGIC The transformation logic is byte-for-byte identical — only the
# MAGIC storage path changes, from a local CSV to the real ADLS Gen2
# MAGIC `bronze/` container your Day 2 Azure Data Factory pipeline populated.
# MAGIC
# MAGIC **Before running:** fill in the three widget values below (storage
# MAGIC account name and access key come from `lab_environment.env`, written
# MAGIC by Day 2's `01_provision_infra.sh`).

# COMMAND ----------

dbutils.widgets.text("storage_account_name", "", "ADLS Storage Account Name")
dbutils.widgets.text("storage_account_key", "", "ADLS Storage Account Key")
dbutils.widgets.text("window_date", "2026-05-01", "Window Date (yyyy-MM-dd)")

storage_account_name = dbutils.widgets.get("storage_account_name")
storage_account_key = dbutils.widgets.get("storage_account_key")
window_date = dbutils.widgets.get("window_date")

# COMMAND ----------

# MAGIC %md
# MAGIC ## Connect to ADLS Gen2
# MAGIC
# MAGIC For this lab we set the account key directly on the Spark session —
# MAGIC fast to set up, fine for a training sandbox. **In production, this
# MAGIC key would live in Azure Key Vault and be referenced via a
# MAGIC Databricks secret scope backed by that same Key Vault** — the exact
# MAGIC Key Vault you built in Day 2, and the exact governance principle
# MAGIC from Day 1's security-by-design lifecycle. We're taking the fast
# MAGIC path today deliberately, and naming it as a shortcut, not a best
# MAGIC practice.

# COMMAND ----------

spark.conf.set(
    f"fs.azure.account.key.{storage_account_name}.dfs.core.windows.net",
    storage_account_key,
)

bronze_path = f"abfss://bronze@{storage_account_name}.dfs.core.windows.net/trades/{window_date}/"
silver_path = f"abfss://silver@{storage_account_name}.dfs.core.windows.net/trades_pyspark/{window_date}/"

print(f"Reading Bronze from: {bronze_path}")
print(f"Will write Silver to: {silver_path}")

# COMMAND ----------

from pyspark.sql import functions as F
from pyspark.sql.window import Window

bronze_df = spark.read.parquet(bronze_path)
print(f"BRONZE row count for {window_date}: {bronze_df.count()}")
display(bronze_df)

# COMMAND ----------

# MAGIC %md
# MAGIC ## Transform: Bronze -> Silver
# MAGIC
# MAGIC Identical logic to Day 2's `usp_transform_trades_to_silver` T-SQL
# MAGIC stored procedure — dedupe by `trade_id` keeping the latest
# MAGIC `last_modified_ts`, filter non-positive quantity/price, compute
# MAGIC `trade_value`. Same rules, expressed as PySpark window functions
# MAGIC instead of `ROW_NUMBER() OVER (...)` and a `MERGE` statement.

# COMMAND ----------

dedupe_window = Window.partitionBy("trade_id").orderBy(F.col("last_modified_ts").desc())

silver_df = (bronze_df
             .withColumn("rn", F.row_number().over(dedupe_window))
             .filter(F.col("rn") == 1)
             .drop("rn")
             .filter(F.col("quantity") > 0)
             .filter(F.col("price") > 0)
             .withColumn("trade_value", F.round(F.col("quantity") * F.col("price"), 2)))

silver_count = silver_df.count()
print(f"SILVER row count for {window_date}: {silver_count}")
print(f"Removed {bronze_df.count() - silver_count} rows during Silver conformance")

# COMMAND ----------

silver_df.write.mode("overwrite").parquet(silver_path)
print(f"Silver written to {silver_path}")
display(silver_df.orderBy("trade_id"))

# COMMAND ----------

# MAGIC %md
# MAGIC ## Checkpoint
# MAGIC
# MAGIC Compare `silver_count` above against the `silver_row_count` your
# MAGIC Day 2 stored procedure returned for the same `window_date` — they
# MAGIC should match exactly. If they don't, check that `window_date`
# MAGIC points at a day you actually ran the Day 2 pipeline for.
