# Fabric Lakehouse Provisioning — Capacity to a Running Pipeline, End to End

**This is the final capstone package.** It automates the complete
sequence: an F2 Fabric capacity in Sweden Central → a workspace on that
capacity → a Lakehouse → a Warehouse → sample data uploaded → the
Bronze → Silver → Gold (+ SCD2) pipeline notebook deployed AND
actually run — not just infrastructure sitting idle.

**Recent update:** every `jq` call in this package has been replaced
with an inline `python3 -c` equivalent — `jq` is no longer a
prerequisite. Look for `# jq -r ...` comments left directly above each
replacement line if you want to compare old vs. new.

**Read "The One Architectural Decision" below before running anything** —
it affects which credentials your `dbt` configuration should actually use.

## Quick Start

```bash
cd scripts
./run_all.sh oaktreefabric01      # pass a unique suffix per person/team
```

Or run each numbered script individually (useful in a live session, to
pause and inspect the Fabric portal between steps):

```bash
./01_create_fabric_capacity.sh oaktreefabric01
./02_create_workspace_and_lakehouse.sh oaktreefabric01
./03_upload_sample_data.sh
./04_create_warehouse_and_get_dbt_creds.sh
./05_deploy_and_run_pipeline.sh          # <-- deploys AND runs the notebook
```

## Prerequisites

- Azure CLI installed and logged in (`az login`), with a subscription
  that has permission to create resources and is registered for
  Microsoft Fabric capacities
- **No `jq` required** (see the update note above)
- `azcopy` installed ([aka.ms/downloadazcopy](https://aka.ms/downloadazcopy)) for script 03
- Enough Azure permissions to create resource groups and Fabric capacities
  (typically Contributor or higher on the subscription/resource group)

## What Gets Created

| Step | Resource | Type |
|---|---|---|
| 1 | Resource Group + Fabric Capacity (F2) | Azure resource (ARM), Sweden Central |
| 2 | Workspace, assigned to the capacity | Fabric-native item |
| 2 | Lakehouse (`oaktree_trades_lh`) | Fabric-native item, inside the workspace |
| 3 | 4 sample CSVs uploaded to `Files/bronze/` | Data inside the Lakehouse |
| 4 | Warehouse (`oaktree_trades_wh`) | Fabric-native item, inside the same workspace |
| 4 | `dbt_fabric_output/profiles.yml` | Generated dbt configuration file |
| 5 | Notebook (`pipeline_bronze_silver_gold_scd2`) | Deployed AND run via the Job Scheduler API |
| 5 | `silver_trades`, `gold_fact_trades_daily`, `gold_dim_trader_scd2` | Real Delta tables, populated by the actual run |

## The One Architectural Decision You Need to Understand

Your Lakehouse's **SQL Analytics Endpoint** (auto-created in step 2,
alongside the Lakehouse itself) is **read-only** — Fabric mirrors
Spark-written Delta tables there for querying, but you cannot `CREATE
TABLE` through it. **dbt needs to write tables.**

That's why step 4 creates a **separate Warehouse item** — this is
Microsoft's own officially supported target for dbt (via the
`dbt-fabric` adapter), and it's what your generated `profiles.yml`
points at. The script also fetches the Lakehouse's read-only SQL
endpoint and prints it, in case you want to query Bronze/Silver data
that a Spark notebook already wrote — but don't try to point dbt's
`profiles.yml` at that endpoint; it will fail on the first `CREATE
TABLE`.

If your goal is instead to have dbt write directly into the *same*
Lakehouse your notebooks use (Spark SQL, not T-SQL), that requires a
different, community-maintained adapter (`type: fabricspark`) — see
"Path B" in `dbt_Project_Reference_and_Fabric_Setup.md` from earlier in
this program for that alternative.

## Using the Generated Credentials

```bash
export DBT_PROFILES_DIR="$(pwd)/dbt_fabric_output"
pip install dbt-fabric
az login   # if your session has expired since provisioning
dbt debug  # confirms the connection before you run anything real
```

Then run your existing `oaktree_dbt` project's `dbt seed && dbt run &&
dbt test` exactly as you did locally — every model, test, and snapshot
file is unchanged. Only the connection target moved from local DuckDB
to a real Fabric Warehouse.

## Step 5 — What Actually Runs, and How to Verify It

Script 5 deploys `notebook/fabric_intro_etl_notebook.py` into the
workspace via the Items API, then triggers it via the Job Scheduler
API (`POST .../jobs/instances?jobType=RunNotebook`) and polls until
it completes — this is the step that turns "infrastructure exists"
into "the pipeline actually ran."

**After it finishes, verify in the Fabric portal:**

1. Open `oaktree_trades_lh` → **Tables** → confirm three new Delta
   tables: `silver_trades`, `gold_fact_trades_daily`, `gold_dim_trader_scd2`.
2. Row counts should match this program's established, verified numbers:
   Silver = 554 rows; the SCD2 dimension should show 6 → 10 rows after
   the June snapshot is applied.
3. Run the point-in-time query from earlier sessions against
   `gold_dim_trader_scd2` to confirm history is genuinely preserved,
   not just present.

If the job fails, the script prints the failure and its
`exitValue` — check the Fabric Monitoring Hub for the full Spark
session log for that run.

## Cost Note — Please Read Before Running

**F2 is Fabric's smallest PAID SKU — this is a real, billed Azure
resource**, unlike the free 60-day trial capacity used in the earlier
"Introducing Microsoft Fabric" session. It bills continuously while
`Active`. To control cost:

```bash
# Pause the capacity (stops billing, keeps the resource) when not in active use:
az fabric capacity suspend --resource-group <rg> --capacity-name <name>

# Resume it later:
az fabric capacity resume --resource-group <rg> --capacity-name <name>

# Or fully remove everything when the exercise is complete:
./99_teardown.sh
```

## Troubleshooting

| Symptom | Likely Cause |
|---|---|
| `az fabric capacity create` fails with a permission error | Your subscription isn't registered for the `Microsoft.Fabric` resource provider, or you lack Contributor rights — check with your Azure admin |
| Script 02 can't find the capacity by name | Fabric-side capacity registration can lag a minute or two behind ARM creation — wait briefly and re-run script 02 |
| `azcopy copy` fails with an auth error | Confirm `az login` succeeded and `AZCOPY_AUTO_LOGIN_TYPE=AZCLI` is set (script 03 sets this automatically) — or run `azcopy login` interactively instead |
| `dbt debug` fails to connect to the Warehouse | Confirm the ODBC Driver 18 for SQL Server is installed locally (a dbt-fabric prerequisite, separate from the Python package) |
| Everything works but tables never appear | Double-check `profiles.yml`'s `host` value is the **Warehouse** connection string, not the Lakehouse SQL endpoint — the two look similar but only one accepts writes |
| Script 5's notebook run fails immediately | Confirm `STORAGE_ACCOUNT_NAME`/`STORAGE_ACCOUNT_KEY` are set as environment variables before calling it (see run_all.sh for the exact export lines) — the notebook needs them as run parameters |
| Script 5 times out waiting for the job | Fabric Spark sessions can take a few minutes to start on a fresh capacity — the poll allows 20 minutes; if it still times out, check the Monitoring Hub directly for a stuck session |
