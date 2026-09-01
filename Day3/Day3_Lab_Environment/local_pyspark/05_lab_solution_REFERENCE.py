"""
05_lab_solution_REFERENCE.py
==============================
FACILITATOR REFERENCE — the completed version of 04_lab_exercise_STARTER.py.
Don't hand this out before teams have attempted the lab themselves.

Run 01_bronze_to_silver.py first so silver_trades_pyspark/ exists.
"""
from pyspark.sql import SparkSession
from pyspark.sql import functions as F

spark = (SparkSession.builder
         .appName("Day3_LabSolution")
         .master("local[*]")
         .getOrCreate())
spark.sparkContext.setLogLevel("ERROR")

DATA_DIR = "../data"

silver_df = spark.read.parquet(f"{DATA_DIR}/_output/silver_trades_pyspark")
dim_trader = (spark.read.option("header", "true").option("inferSchema", "true")
              .csv(f"{DATA_DIR}/dim_trader.csv"))

# TODO 1 SOLUTION — flag large trades for manual review
flagged_df = silver_df.withColumn("needs_review", F.col("trade_value") > 5000000)

# TODO 2 SOLUTION — broadcast join to enrich with trader/desk info
enriched_df = flagged_df.join(F.broadcast(dim_trader), on="trader_id", how="left")

# TODO 3 SOLUTION — aggregate by desk and review flag
desk_review_summary = (enriched_df
                        .groupBy("desk", "needs_review")
                        .agg(
                            F.sum("trade_value").alias("total_trade_value"),
                            F.count("*").alias("flagged_trade_count"),
                        )
                        .orderBy(F.desc("total_trade_value")))

print("=" * 70)
print("TODO 3 RESULT — by desk and review flag")
print("=" * 70)
desk_review_summary.show(truncate=False)

# TODO 4 SOLUTION — which desk has the most flagged value, as a % of its total?
desk_totals = (enriched_df.groupBy("desk")
               .agg(F.sum("trade_value").alias("desk_total_value")))

flagged_only = (enriched_df.filter(F.col("needs_review"))
                .groupBy("desk")
                .agg(F.sum("trade_value").alias("flagged_value")))

pct_df = (flagged_only.join(desk_totals, on="desk")
          .withColumn("pct_of_desk_total", F.round(F.col("flagged_value") / F.col("desk_total_value") * 100, 1))
          .orderBy(F.desc("flagged_value")))

print("=" * 70)
print("TODO 4 RESULT — flagged value as % of each desk's total")
print("=" * 70)
pct_df.show(truncate=False)

top_row = pct_df.orderBy(F.desc("flagged_value")).first()
print(f"\nANSWER: The {top_row['desk']} desk has the highest flagged value "
      f"({top_row['flagged_value']:,.0f}), representing {top_row['pct_of_desk_total']}% "
      f"of that desk's total trade value.")

spark.stop()
