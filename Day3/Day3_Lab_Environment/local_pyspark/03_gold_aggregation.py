"""
03_gold_aggregation.py
=======================
Builds the Gold layer: aggregates Silver into the exact star-schema shape
from Day 1 (fact_trades_daily), ready for Day 6's Power BI semantic model.
Run 01_bronze_to_silver.py first.

Run it:
    python3 03_gold_aggregation.py
"""
from pyspark.sql import SparkSession
from pyspark.sql import functions as F

spark = (SparkSession.builder
         .appName("Day3_GoldAggregation")
         .master("local[*]")
         .getOrCreate())
spark.sparkContext.setLogLevel("ERROR")

DATA_DIR = "../data"

silver_df = spark.read.parquet(f"{DATA_DIR}/_output/silver_trades_pyspark")
dim_security = (spark.read.option("header", "true").option("inferSchema", "true")
                 .csv(f"{DATA_DIR}/dim_security.csv"))

# GOLD — one row per (date, security, trade_type), matching the exact
# grain used in Day 1's SQL demo and Day 6's DAX measures.
gold_df = (silver_df
           .join(F.broadcast(dim_security), on="security_id", how="left")
           .groupBy("trade_date", "asset_class", "trade_type")
           .agg(
               F.sum("trade_value").alias("total_trade_value"),
               F.count("*").alias("trade_count"),
               F.round(F.avg("price"), 2).alias("avg_price"),
           )
           .orderBy("trade_date", F.desc("total_trade_value")))

print(f"GOLD row count: {gold_df.count()}")
gold_df.write.mode("overwrite").parquet(f"{DATA_DIR}/_output/gold_trades_daily_pyspark")
print(f"Gold output written to {DATA_DIR}/_output/gold_trades_daily_pyspark/")

print("\nTop 10 rows by total_trade_value:")
gold_df.orderBy(F.desc("total_trade_value")).show(10, truncate=False)

# Sanity-check against Day 1's May 2026 sample query framing
may_total = (gold_df.filter(F.month("trade_date") == 5)
             .agg(F.sum("total_trade_value")).collect()[0][0])
print(f"\nTotal May 2026 trade value across all rows: {may_total:,.2f}")

spark.stop()
