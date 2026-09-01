"""
02_distributed_processing_demo.py
==================================
Demonstrates the distributed-processing concepts from today's lecture using
the REAL Silver output from script 01 and the dim_security/dim_trader
reference data — not toy numbers. Run 01_bronze_to_silver.py first.

Concepts shown, in order:
  1. Partition count and how to inspect/change it
  2. A shuffle-heavy operation (groupBy) and how to read its query plan
  3. A broadcast join against small dimension tables (the fast way to
     enrich fact_trades with security/trader names)
  4. Caching a DataFrame that's reused multiple times

Run it:
    python3 02_distributed_processing_demo.py
"""
from pyspark.sql import SparkSession
from pyspark.sql import functions as F

spark = (SparkSession.builder
         .appName("Day3_DistributedProcessing")
         .master("local[4]")   # 4 partitions worth of parallelism, enough to see partitioning behavior
         .getOrCreate())
spark.sparkContext.setLogLevel("ERROR")

DATA_DIR = "../data"

silver_df = spark.read.parquet(f"{DATA_DIR}/_output/silver_trades_pyspark")

# ---------------------------------------------------------------------
# 1. PARTITIONS — the unit of parallelism
# ---------------------------------------------------------------------
print("=" * 70)
print("1. PARTITIONS")
print("=" * 70)
print(f"Default partition count after reading Parquet: {silver_df.rdd.getNumPartitions()}")

repartitioned = silver_df.repartition(4, "security_id")
print(f"After repartition(4, 'security_id'): {repartitioned.rdd.getNumPartitions()}")
print("Repartitioning by security_id means all rows for the same security land")
print("in the same partition — useful before a groupBy or join on that column.\n")

# ---------------------------------------------------------------------
# 2. SHUFFLE — what a groupBy actually costs
# ---------------------------------------------------------------------
print("=" * 70)
print("2. SHUFFLE (groupBy triggers a shuffle across partitions)")
print("=" * 70)
daily_totals = (silver_df.groupBy("trade_date", "trade_type")
                 .agg(F.sum("trade_value").alias("total_value"), F.count("*").alias("trade_count")))
daily_totals.explain()   # shows the physical plan, including the Exchange (shuffle) step
print()

# ---------------------------------------------------------------------
# 3. BROADCAST JOIN — enrich fact_trades with small dimension tables
#    WITHOUT shuffling the (much larger) fact table
# ---------------------------------------------------------------------
print("=" * 70)
print("3. BROADCAST JOIN — enrich with dim_security and dim_trader")
print("=" * 70)
dim_security = (spark.read.option("header", "true").option("inferSchema", "true")
                 .csv(f"{DATA_DIR}/dim_security.csv"))
dim_trader = (spark.read.option("header", "true").option("inferSchema", "true")
              .csv(f"{DATA_DIR}/dim_trader.csv"))

enriched_df = (silver_df
               .join(F.broadcast(dim_security), on="security_id", how="left")
               .join(F.broadcast(dim_trader), on="trader_id", how="left"))

print(f"Enriched row count (should still be {silver_df.count()}, a join, not an aggregation):")
print(enriched_df.count())
enriched_df.select("trade_id", "trade_date", "ticker", "asset_class", "trader_name", "desk", "trade_value") \
    .orderBy("trade_date").show(8, truncate=False)

# ---------------------------------------------------------------------
# 4. CACHING — avoid recomputing a DataFrame referenced multiple times
# ---------------------------------------------------------------------
print("=" * 70)
print("4. CACHING")
print("=" * 70)
enriched_df.cache()
enriched_df.count()  # materializes the cache (an action, per the lazy-evaluation rule)
print("enriched_df is now cached in memory — the next two aggregations below")
print("reuse it directly instead of re-reading CSVs and re-joining from scratch.\n")

by_desk = enriched_df.groupBy("desk").agg(F.sum("trade_value").alias("total_value"))
by_asset_class = enriched_df.groupBy("asset_class").agg(F.sum("trade_value").alias("total_value"))

print("Total trade value by desk:")
by_desk.orderBy(F.desc("total_value")).show()
print("Total trade value by asset class:")
by_asset_class.orderBy(F.desc("total_value")).show()

spark.stop()
