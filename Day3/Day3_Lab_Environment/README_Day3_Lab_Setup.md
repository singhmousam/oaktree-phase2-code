# Day 3 Lab Environment — Data Transformation & Distributed Processing

Two complete, parallel ways to do today's lab — pick based on what's
provisioned and how much time is available:

| Path | Use When | Folder |
|---|---|---|
| **Local PySpark** | No Databricks access yet, want instant feedback, or practicing before/after class | `local_pyspark/` |
| **Real Databricks cluster** | Day 2's Azure environment is up and you want the genuine cloud experience | `databricks_notebooks/` + `scripts/` |

Both paths run the **exact same transformation logic** — the local path
proves your logic is correct before you spend cluster time; the Databricks
path proves it at real, multi-node scale against the real ADLS Gen2 data
Day 2's ADF pipeline produced.

## Path A — Local PySpark (fastest to start)

```bash
cd local_pyspark
pip install pyspark --break-system-packages
python3 01_bronze_to_silver.py
python3 02_distributed_processing_demo.py
python3 03_gold_aggregation.py
python3 04_lab_exercise_STARTER.py      # complete the 4 TODOs
python3 05_lab_solution_REFERENCE.py    # compare afterward
```

See `local_pyspark/README.md` for verified expected output at every step.

## Path B — Real Azure Databricks Cluster

```bash
cd scripts
./01_provision_databricks.sh oaktreelab-team1   # creates workspace + cluster + imports notebooks
# wait ~5 minutes for the cluster to start, then open the workspace URL printed at the end

# Optional: trigger all three main notebooks end-to-end without touching the UI
./02_run_notebooks_e2e.sh 2026-05-01 <storage_account_name> <storage_account_key>

# At the end of the day:
./99_teardown_databricks.sh
```

Or follow `docs/Day3_Azure_Portal_StepByStep.md` to do every one of these
steps by clicking through the Azure Portal and Databricks workspace UI
instead of running the script — useful for understanding exactly what the
script automates, or if your training environment restricts CLI access.

## Directory layout

```
day3_lab/
├── README_Day3_Lab_Setup.md         <- this file
├── data/                             <- same sample dataset as Day 2 (trade_blotter.csv, dim_security.csv, dim_trader.csv)
├── local_pyspark/
│   ├── README.md                     <- verified expected outputs for every script
│   ├── 01_bronze_to_silver.py
│   ├── 02_distributed_processing_demo.py
│   ├── 03_gold_aggregation.py
│   ├── 04_lab_exercise_STARTER.py
│   └── 05_lab_solution_REFERENCE.py
├── databricks_notebooks/             <- identical logic, cluster-ready (.py, Databricks source format)
│   ├── 01_bronze_to_silver.py
│   ├── 02_distributed_processing_demo.py
│   ├── 03_gold_aggregation.py
│   ├── 04_lab_exercise_STARTER.py
│   └── 05_lab_solution_REFERENCE.py
├── scripts/
│   ├── 01_provision_databricks.sh    <- creates workspace, cluster, imports all 5 notebooks
│   ├── 02_run_notebooks_e2e.sh       <- runs notebooks 1-3 via the Jobs API, no UI needed
│   └── 99_teardown_databricks.sh
└── docs/
    ├── Day3_Azure_Portal_StepByStep.md
    └── Day2_Azure_Portal_StepByStep.md
```

## How this feeds the rest of the program

| Day | What it reads from today's output |
|---|---|
| Day 4 (Fabric) | The exact same Bronze/Silver transformation logic moves into a Fabric notebook — only I/O paths change, again |
| Day 6 (Power BI) | `gold_trades_daily` (registered as a table in Notebook 3) is the semantic model source |
| Day 9 (Capstone) | Teams choose PySpark/Databricks or Fabric notebooks for their transformation layer — today is direct practice for that choice |
