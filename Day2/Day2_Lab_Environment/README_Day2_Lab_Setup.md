# Day 2 Lab Environment — Azure Data Engineering Stack

This is the complete, scripted lab environment for Day 2 (Module 2: Azure
Data Engineering Stack). It provisions a real, working, end-to-end Azure
Data Factory pipeline — ingestion **and** transformation — built around the
exact OakTree trade blotter case study introduced on Day 1, and it hands off
directly into Day 3 (PySpark), Day 4 (Fabric), and beyond.

## What gets built

```
Azure SQL Database (source)          ADLS Gen2 (lakehouse)
┌─────────────────────────┐          ┌───────────────────┐
│ dbo.trade_blotter        │  Copy   │ bronze/trades/...  │
│  (raw, "Oracle" stand-in)│ ──────► │ (raw Parquet copy)  │
└─────────────────────────┘          └───────────────────┘
            │
            │ Stored Procedure Activity
            │ usp_transform_trades_to_silver
            ▼
┌─────────────────────────┐          ┌───────────────────┐
│ dbo.trade_blotter_silver │  Copy   │ silver/trades/...  │
│  (deduped, cleaned,      │ ──────► │ (cleaned Parquet)   │
│   trade_value computed)  │         └───────────────────┘
└─────────────────────────┘
```

All three activities run inside **one ADF pipeline**
(`PL_TradeBlotter_Bronze_to_Silver`), triggered daily by a Schedule Trigger,
with a failure-notification path — matching Day 1's "no silent failures"
security-by-design principle.

## Directory layout

```
day2_lab/
├── README_Day2_Lab_Setup.md        <- this file
├── data/
│   ├── trade_blotter.csv           <- 567-row sample "Oracle export" (generated)
│   ├── dim_security.csv            <- 8 securities
│   └── dim_trader.csv              <- 6 traders
├── scripts/
│   ├── generate_sample_data.py     <- regenerate the CSVs (seeded/deterministic)
│   ├── 01_provision_infra.sh       <- creates ALL Azure resources
│   ├── 03_deploy_adf_pipeline.sh   <- deploys the ADF artifacts via Azure CLI
│   └── 99_teardown.sh              <- deletes everything when you're done
├── sql/
│   └── 02_setup_source_database.sql <- creates tables + the transform stored proc
└── adf_artifacts/
    ├── 01_linkedService_KeyVault.json
    ├── 02_linkedService_AzureSqlDatabase.json
    ├── 03_linkedService_ADLS.json
    ├── 04_dataset_SqlTradeBlotter.json
    ├── 05_dataset_ADLS_Bronze.json
    ├── 06_dataset_SqlTradeBlotterSilver.json
    ├── 07_dataset_ADLS_Silver.json
    ├── 08_pipeline_TradeBlotter.json
    └── 09_trigger_Daily.json
```

## Run order (do this once per participant/team before Day 2)

### Linux prerequisites

The deployment script uses `jq` to extract the inner `properties` object from
each ADF JSON artifact. Install it once on the Linux VDI before deployment:

```bash
# Ubuntu/Debian
sudo apt-get update && sudo apt-get install -y jq

# RHEL/Fedora
sudo dnf install -y jq

# Alpine
sudo apk add jq
```

```bash
cd Day2/Day2_Lab_Environment/scripts

# 1. Provision everything: Resource Group, SQL Server+DB, Storage (ADLS Gen2),
#    Key Vault, Data Factory, and least-privilege role assignments.
./01_provision_infra.sh oaktreelab-team1        # pass a unique suffix per team

# On 'RequestDisallowedByPolicy' error allow the specific resources as needed for this run
az provider register --namespace Microsoft.Sql 
az provider register --namespace Microsoft.DataLakeStore
az provider register --namespace Microsoft.DataFactory

# 2. Add your IP to the SQL firewall (printed by step 1), then run the SQL
#    setup script against the new database — creates tables, the stored
#    procedure, and seeds a 10-row quick-start sample.
#    (Use Azure Data Studio, SSMS, or `sqlcmd -S <fqdn> -d <db> -U <user> -i ../sql/02_setup_source_database.sql`)

# 2b. OPTIONAL but recommended: bulk-load the full 567-row data/trade_blotter.csv
#     (see the bulk-load notes at the bottom of 02_setup_source_database.sql)

# 3. Deploy the ADF linked services, datasets, pipeline, and trigger.
./03_deploy_adf_pipeline.sh

# 4. Run the pipeline for a specific day (instructions printed at the end of step 3),
#    or trigger it manually from ADF Studio's Author tab.

# 5. When the training day (or the whole program) is done:
./99_teardown.sh
```

## Regenerating the sample data

`data/trade_blotter.csv` was produced by `scripts/generate_sample_data.py`
with a fixed random seed, so it's fully reproducible:

```bash
python3 scripts/generate_sample_data.py
```

It deliberately includes:
- **567 total rows** across 31 business days (2026-05-01 through 2026-06-12)
- **8 duplicate rows** (simulating a retried/partially-failed nightly load)
- **5 bad records** (negative quantity or zero price — realistic data-entry errors)

This messiness is exactly what `usp_transform_trades_to_silver` cleans up —
verified with DuckDB during development: **567 Bronze rows → 554 Silver
rows** after de-duplication (keeping the latest `last_modified_ts` per
`trade_id`) and filtering non-positive quantity/price.

## Cost notes

- SQL Database uses the **Serverless** compute tier with a 60-minute
  auto-pause — it costs nothing while idle.
- Storage Account uses **Standard LRS** — the cheapest redundancy tier,
  appropriate for a training sandbox (not for production).
- Run `99_teardown.sh` at the end of the day if this is a shared or
  temporary training subscription.

## How this feeds the rest of the program

| Day | What it reads from this environment |
|---|---|
| Day 3 (PySpark) | Reads `silver/trades/` Parquet files directly, or re-derives Silver from `bronze/trades/` using the same dedupe/filter logic, now in PySpark instead of T-SQL |
| Day 4 (Fabric) | A Fabric Lakehouse Shortcuts to this same ADLS Gen2 storage account instead of re-uploading anything |
| Day 6 (Power BI) | The semantic model and DAX measures are built on a Gold table derived from this same `trade_blotter_silver` shape |
| Day 7 (Migration) | This IS the "modernized" version of the Day 1 legacy case — the roadmap you built on Day 1 describes exactly this build |
| Day 8 (Governance) | The Key Vault + managed-identity + least-privilege role assignment pattern here is the concrete implementation of Day 8's access control matrix |

## Notes
- Dataset parameter: {layer}/{trades/@{dataset().windowDate}}

- Pipeline builder: SELECT trade_id, trade_date, security_id, trader_id, trade_type, quantity, price, last_modified_ts FROM dbo.trade_blotter WHERE trade_date = '@{pipeline().parameters.windowDate}'
- Experssion builder: @pipeline().parameters.windowDate

