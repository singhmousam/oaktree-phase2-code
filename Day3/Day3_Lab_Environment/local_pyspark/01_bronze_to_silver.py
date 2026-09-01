"""
01_bronze_to_silver.py
=======================
LOCAL PRACTICE VERSION — runs on your laptop with local[*] Spark, no cluster
or Azure access needed. Same PySpark API you'll use on a real Databricks
cluster this afternoon (see databricks_notebooks/ for the cluster version).

Reads the real 567-row trade_blotter.csv (the same file Day 2's Azure SQL
Database was seeded from), and reproduces the Bronze -> Silver transformation
—this time in PySpark instead of T-SQL. If you completed Day 2, compare this
script's output row count to the trade_blotter_silver table you built there:
they should match exactly (554 rows) because it's the identical logic,
expressed in two different tools.

Run it:
    python3 01_bronze_to_silver.py
"""
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.window import Window

spark = (SparkSession.builder
         .appName("Day3_BronzeToSilver")
         .master("local[*]")
         .getOrCreate())
spark.sparkContext.setLogLevel("ERROR")

DATA_DIR = "../data"

# ---------------------------------------------------------------------
# BRONZE — read the raw CSV exactly as it landed (this is what a real
# Databricks notebook would do reading from abfss://bronze@<storage>.../)
# ---------------------------------------------------------------------
bronze_df = (spark.read
             .option("header", "true")
             .option("inferSchema", "true")
             .csv(f"{DATA_DIR}/trade_blotter.csv"))

print(f"BRONZE row count: {bronze_df.count()}")
bronze_df.printSchema()

# ---------------------------------------------------------------------
# SILVER — dedupe (keep latest last_modified_ts per trade_id), filter
# non-positive quantity/price, compute trade_value. This is the EXACT
# same logic as Day 2's usp_transform_trades_to_silver stored procedure,
# now expressed as PySpark window functions and DataFrame transforms
# instead of T-SQL's ROW_NUMBER() OVER (...) and a MERGE statement.
# ---------------------------------------------------------------------
dedupe_window = Window.partitionBy("trade_id").orderBy(F.col("last_modified_ts").desc())

silver_df = (bronze_df
             .withColumn("rn", F.row_number().over(dedupe_window))
             .filter(F.col("rn") == 1)
             .drop("rn")
             .filter(F.col("quantity") > 0)
             .filter(F.col("price") > 0)
             .withColumn("trade_value", F.round(F.col("quantity") * F.col("price"), 2))
             .withColumn("trade_date", F.to_date("trade_date")))

silver_count = silver_df.count()
print(f"SILVER row count: {silver_count}")
removed = bronze_df.count() - silver_count
print(f"Removed {removed} rows during Silver conformance (duplicates + bad records)")

# Persist locally as Parquet, mirroring the ADLS silver/trades/ layout from Day 2
silver_df.write.mode("overwrite").parquet(f"{DATA_DIR}/_output/silver_trades_pyspark")
print(f"Silver output written to {DATA_DIR}/_output/silver_trades_pyspark/")

silver_df.orderBy("trade_date", "trade_id").show(10, truncate=False)

spark.stop()
