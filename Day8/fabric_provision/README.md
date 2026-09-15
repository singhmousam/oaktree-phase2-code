# Fabric Lakehouse Provisioning — Capacity to dbt-Ready in One Script Chain

Automates exactly the sequence you asked for: an F2 Fabric capacity in
Sweden Central → a workspace on that capacity → a Lakehouse → sample
data uploaded → connection credentials for dbt.

**Read "The One Architectural Decision" below before running anything** —
it affects which credentials your `dbt` configuration should actually use.

## Quick Start

```bash
cd scripts
./run_all.sh oaktreefabric01      # remember to pass a unique suffix per person/team
```

Or run each numbered script individually (useful in a live session, to
pause and inspect the Fabric portal between steps):

```bash
./01_create_fabric_capacity.sh oaktreefabric01
./02_create_workspace_and_lakehouse.sh oaktreefabric01
./03_upload_sample_data.sh
./04_create_warehouse_and_get_dbt_creds.sh
```

## Prerequisites

- Azure CLI installed and logged in (`az login`), with a subscription
  that has permission to create resources and is registered for
  Microsoft Fabric capacities
- `jq` installed (JSON parsing in the helper scripts)
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
