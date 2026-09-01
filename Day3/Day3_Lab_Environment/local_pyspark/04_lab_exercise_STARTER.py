"""
04_lab_exercise_STARTER.py
===========================
HANDS-ON LAB — complete the TODOs below. Run 01_bronze_to_silver.py first
so silver_trades_pyspark/ exists.

This mirrors the Day 2 lab format: you're extending a working pipeline,
not building one from scratch. Everything up to the TODOs is provided and
already runs; your job is to add the four pieces marked TODO.

When you're done, compare your output against 05_lab_solution_REFERENCE.py
(don't peek before attempting it yourself!).
"""
from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.window import Window

spark = (SparkSession.builder
         .appName("Day3_LabExercise")
         .master("local[*]")
         .getOrCreate())
spark.sparkContext.setLogLevel("ERROR")

DATA_DIR = "../data"

silver_df = spark.read.parquet(f"{DATA_DIR}/_output/silver_trades_pyspark")
dim_trader = (spark.read.option("header", "true").option("inferSchema", "true")
              .csv(f"{DATA_DIR}/dim_trader.csv"))

# ---------------------------------------------------------------------
# TODO 1: Add a new data quality rule.
# The current Silver logic (in script 01) already filters quantity > 0
# and price > 0. Real trading desks also flag trades above a notional
# threshold for manual review. Add a new boolean column, needs_review,
# that is True when trade_value > 5,000,000.
#
# Hint: use .withColumn("needs_review", F.col("trade_value") > 5000000)
# ---------------------------------------------------------------------
flagged_df = silver_df  # <-- replace this line with your withColumn(...) call


# ---------------------------------------------------------------------
# TODO 2: Enrich with trader information using a BROADCAST JOIN.
# Join flagged_df to dim_trader on trader_id, using a left join, and
# make sure you broadcast the small dimension table (dim_trader) —
# not the large fact table — exactly like Code Demo 3 did with
# dim_security.
# ---------------------------------------------------------------------
enriched_df = flagged_df  # <-- replace this line with your .join(F.broadcast(...), ...) call


# ---------------------------------------------------------------------
# TODO 3: Aggregate by desk and needs_review flag.
# Produce a DataFrame grouped by (desk, needs_review) with:
#   - total_trade_value (sum of trade_value)
#   - flagged_trade_count (count of rows)
# Order the result by total_trade_value descending.
# ---------------------------------------------------------------------
desk_review_summary = enriched_df  # <-- replace this line with your .groupBy(...).agg(...) call


# ---------------------------------------------------------------------
# TODO 4: Answer this question in a comment, then print your answer.
# Which desk has the highest total value of trades flagged for review,
# and what percentage of that desk's total trade value does that represent?
# (You'll need a second aggregation, un-filtered by needs_review, to get
#  the denominator — think about how you'd structure that query.)
# ---------------------------------------------------------------------
# YOUR ANSWER HERE (as a comment):
#
#


print("=" * 70)
print("YOUR RESULTS")
print("=" * 70)
desk_review_summary.show(truncate=False)

spark.stop()
