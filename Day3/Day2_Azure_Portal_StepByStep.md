# Day 2 — Building the Pipeline from the Azure Portal (No Scripts)

This document walks through **everything `01_provision_infra.sh` and
`03_deploy_adf_pipeline.sh` automate**, but by clicking through the Azure
Portal and ADF Studio instead. Use this if:

- Your training environment restricts CLI/script access
- You want to *see* what each resource looks like as you create it
- You're teaching yourself the portal UI before relying on scripts

Every section header names the exact script step it replaces, so you can
cross-reference `README_Day2_Lab_Setup.md` at any point.

> **UI note:** Azure Portal screens are updated frequently. Button labels
> and blade layouts below reflect the portal as of this program's writing —
> if something has moved, the *resource types and settings* below are still
> accurate; use the Portal's search bar to find the equivalent screen.

---

## Part 1 — Resource Group

*(Replaces: `01_provision_infra.sh`, section 1)*

1. Go to [portal.azure.com](https://portal.azure.com) and sign in.
2. Search the top bar for **"Resource groups"** → click **+ Create**.
3. Subscription: select your training subscription.
4. Resource group name: `rg-oaktreelab-<yourname>` (use something unique per person/team).
5. Region: **Central India** (or whichever region your trainer specifies — keep every resource in the same region for this lab).
6. Click **Review + create** → **Create**.

---

## Part 2 — Azure SQL Database (the "legacy Oracle" stand-in)

*(Replaces: `01_provision_infra.sh`, section 2)*

### 2a. Create the logical SQL Server

1. In the search bar, type **"SQL servers"** → **+ Create**.
2. Resource group: the one from Part 1.
3. Server name: `sql-oaktreelab-<yourname>` (must be globally unique).
4. Location: same region as your resource group.
5. Authentication method: **Use SQL authentication**.
6. Server admin login: `oaktreeadmin` — Password: choose a strong password and **write it down**, you'll need it repeatedly today.
7. Click **Review + create** → **Create**. Wait for deployment to finish (~1 minute).

### 2b. Create the Database

1. Go to your new SQL Server's page → click **+ Create database** (or search "SQL databases" → **+ Create**).
2. Database name: `oaktree_trades_db`.
3. Compute + storage: click **Configure database** → change **Service tier** to **General Purpose** → **Serverless** → set **Auto-pause delay** to **1 hour**. This keeps cost near-zero while idle.
4. Click **Apply** → **Review + create** → **Create**.

### 2c. Open the firewall so you (and Azure services) can connect

1. Go to your SQL Server's page → left menu → **Networking**.
2. Under **Firewall rules**, toggle **"Allow Azure services and resources to access this server"** to **Yes**.
3. Click **+ Add your client IPv4 address** (the portal detects it automatically).
4. Click **Save**.

### 2d. Run the setup SQL script

1. Go to your database's page → left menu → **Query editor (preview)**.
2. Sign in with the `oaktreeadmin` credentials from step 2a.
3. Open `sql/02_setup_source_database.sql` from the lab files, copy its full contents.
4. Paste into the Query editor and click **Run**.
5. Confirm success: run `SELECT COUNT(*) FROM dbo.trade_blotter;` — you should see 10 rows (the quick-start seed). To load the full 567-row sample, use the Query editor's **Import data** option or follow the bulk-load notes at the bottom of the SQL script file.

---

## Part 3 — ADLS Gen2 Storage Account (the lakehouse)

*(Replaces: `01_provision_infra.sh`, section 3)*

1. Search **"Storage accounts"** → **+ Create**.
2. Resource group: same as before. Storage account name: `stoaktreelabdata<yourname>` (lowercase, no hyphens, globally unique).
3. Region: same as before. Performance: **Standard**. Redundancy: **LRS** (cheapest, fine for training).
4. Click the **Advanced** tab → under **Data Lake Storage Gen2**, check **Enable hierarchical namespace**. This is the single most important checkbox in this whole section — without it, this is just Blob Storage, not a lakehouse.
5. Click **Review + create** → **Create**.
6. Once deployed, go to the storage account → left menu → **Containers** → **+ Container**. Create two containers named exactly `bronze` and `silver` (Public access level: **Private**).

---

## Part 4 — Key Vault (secrets)

*(Replaces: `01_provision_infra.sh`, section 4)*

1. Search **"Key vaults"** → **+ Create**.
2. Resource group: same as before. Key vault name: `kv-oaktreelab-<yourname>`.
3. Region: same as before. Pricing tier: **Standard**.
4. Click **Review + create** → **Create**.
5. Once deployed, go to the vault → left menu → **Objects → Secrets** → **+ Generate/Import**.
6. Name: `sql-admin-password`. Value: the SQL admin password from Part 2a. Click **Create**.
7. Repeat for a secret named `sql-connection-string` if you want it handy (value: the full ADO.NET connection string using your server/database/user).

---

## Part 5 — Azure Data Factory

*(Replaces: `01_provision_infra.sh`, section 5)*

1. Search **"Data factories"** → **+ Create**.
2. Resource group: same as before. Name: `adf-oaktreelab-<yourname>`.
3. Region: same as before. Version: **V2**.
4. Click **Review + create** → **Create**. Once deployed, click **Go to resource**, then **Launch studio** to open ADF Studio in a new tab — you'll spend most of the rest of this guide there.

---

## Part 6 — Least-Privilege Role Assignments

*(Replaces: `01_provision_infra.sh`, sections 6)*

### 6a. Grant ADF's managed identity access to Storage

1. Go to your **Storage account** → left menu → **Access Control (IAM)** → **+ Add** → **Add role assignment**.
2. Role: search for and select **Storage Blob Data Contributor** → **Next**.
3. Assign access to: **Managed identity** → **+ Select members** → Managed identity type: **Data Factory (V2)** → select your `adf-oaktreelab-<yourname>` factory → **Select**.
4. Click **Review + assign**.

### 6b. Grant ADF's managed identity access to Key Vault secrets

1. Go to your **Key Vault** → left menu → **Access configuration**. If it shows "Vault access policy" (not RBAC), go to **Access policies** → **+ Create**.
2. Secret permissions: check **Get** and **List**.
3. Principal: search for your Data Factory's name (`adf-oaktreelab-<yourname>`) — it appears because ADF has a system-assigned managed identity.
4. Click **Next** through the wizard → **Create**.

*(If your vault uses the newer "Azure RBAC" permission model instead, do the same as 6a but with role **Key Vault Secrets User** scoped to the vault.)*

---

## Part 7 — Build the Pipeline in ADF Studio

*(Replaces: `03_deploy_adf_pipeline.sh`, all 9 steps — this is the longest part)*

Open **ADF Studio** (from Part 5) → click the pencil icon (**Author**) on the left rail.

### 7a. Linked Service: Key Vault

1. Under **Manage** (toolbox icon) → **Linked services** → **+ New**.
2. Search for and select **Azure Key Vault** → **Continue**.
3. Name: `LS_KeyVault_OakTree`.
4. Azure Key Vault selection method: **From Azure subscription** → select your subscription and the vault from Part 4.
5. Click **Test connection**, confirm it succeeds, then **Create**.

### 7b. Linked Service: Azure SQL Database

1. **+ New** → search **Azure SQL Database** → **Continue**.
2. Name: `LS_AzureSqlDatabase_OakTreeSource`.
3. Server name / Database name: select your server and `oaktree_trades_db` from the dropdowns (ADF discovers them automatically once you pick your subscription).
4. Authentication type: **SQL authentication**. User name: `oaktreeadmin`.
5. Password: click **Azure Key Vault** as the source instead of typing it → select `LS_KeyVault_OakTree` as the linked service → Secret name: `sql-admin-password`.
6. **Test connection** → **Create**.

### 7c. Linked Service: ADLS Gen2

1. **+ New** → search **Azure Data Lake Storage Gen2** → **Continue**.
2. Name: `LS_ADLS_OakTreeLake`.
3. Authentication method: **System Assigned Managed Identity**.
4. Account selection method: **From Azure subscription** → pick your storage account.
5. **Test connection** (this only succeeds if Part 6a's role assignment is in place) → **Create**.

### 7d. Datasets (create all four)

For each, go to **Author** → **Datasets** → **+ (new dataset)**:

| Dataset name | Type | Linked Service | Key settings |
|---|---|---|---|
| `DS_Sql_TradeBlotter` | Azure SQL Database | `LS_AzureSqlDatabase_OakTreeSource` | Table: `dbo.trade_blotter` |
| `DS_ADLS_Bronze_Trades` | Parquet (in ADLS Gen2) | `LS_ADLS_OakTreeLake` | File path: container `bronze`, folder `trades/@{windowDate}` — click the dataset's **Parameters** tab first and add a string parameter named `windowDate`, then reference it in the folder path via the pencil/dynamic-content icon |
| `DS_Sql_TradeBlotterSilver` | Azure SQL Database | `LS_AzureSqlDatabase_OakTreeSource` | Table: `dbo.trade_blotter_silver` |
| `DS_ADLS_Silver_Trades` | Parquet (in ADLS Gen2) | `LS_ADLS_OakTreeLake` | File path: container `silver`, folder `trades/@{windowDate}` (same `windowDate` parameter pattern) |

### 7e. The Pipeline

1. **Author** → **Pipelines** → **+ New pipeline**. Name: `PL_TradeBlotter_Bronze_to_Silver`.
2. Click the pipeline's blank canvas → **Parameters** tab → **+ New** → name `windowDate`, type **String**, default value `2026-05-01`.
3. **Activity 1 — Copy Blotter to Bronze:** drag a **Copy data** activity onto the canvas, rename it `Copy_Blotter_To_Bronze`.
   - **Source** tab: dataset `DS_Sql_TradeBlotter`. Under "Use query", switch to **Query** and paste: `SELECT trade_id, trade_date, security_id, trader_id, trade_type, quantity, price, last_modified_ts FROM dbo.trade_blotter WHERE trade_date = '@{pipeline().parameters.windowDate}'` (use the dynamic content editor, not literal text, for the `@{...}` part).
   - **Sink** tab: dataset `DS_ADLS_Bronze_Trades` → set its `windowDate` parameter to the pipeline's `windowDate` (dynamic content: `@pipeline().parameters.windowDate`).
   - **Settings** tab: under **Retry**, set Retry count `3`, Retry interval `60` seconds.
4. **Activity 2 — Transform:** drag a **Stored Procedure** activity, rename it `Transform_Bronze_To_Silver`. Connect a green **Success** arrow from Activity 1 to this one.
   - **Settings** tab: Linked service `LS_AzureSqlDatabase_OakTreeSource`. Stored procedure name: `[dbo].[usp_transform_trades_to_silver]`. Click **Import parameter** → set `WindowDate` value to `@pipeline().parameters.windowDate`.
5. **Activity 3 — Copy Silver to Lake:** drag another **Copy data** activity, rename it `Copy_Silver_To_Lake`. Connect a green **Success** arrow from Activity 2.
   - **Source**: dataset `DS_Sql_TradeBlotterSilver`, query filtered the same way on `trade_date`.
   - **Sink**: dataset `DS_ADLS_Silver_Trades`, `windowDate` parameter wired the same way.
6. **Activity 4 — Failure notification:** drag a **Web** activity, rename it `Notify_On_Failure`. Connect a **red Failure arrow** from *each* of the three activities above into this one (right-click each activity's edge to pick "Failure" as the connection type).
   - **Settings**: URL — a Teams/Logic App webhook if you have one, or a placeholder for now. Method: **POST**. Body: `{"text": "Pipeline failed for windowDate=@{pipeline().parameters.windowDate}"}`.
7. Click **Debug** at the top to test-run the pipeline immediately, entering a `windowDate` when prompted (e.g., `2026-05-01`). Watch the activities turn green one at a time in the output pane at the bottom.
8. Click **Publish all** (top left) once you're happy — Debug runs don't need publishing, but a real Trigger does.

### 7f. The Trigger

1. On the pipeline canvas, click **Add trigger** → **New/Edit** → **+ New**.
2. Name: `TR_Daily_3AM_TradeBlotter`. Type: **Schedule**.
3. Recurrence: every `1` **Day**, start time `2026-05-02T03:00:00Z`, time zone **UTC**.
4. Click **OK**, then on the next screen set the `windowDate` parameter's value using dynamic content: `@formatDateTime(addDays(trigger().scheduledTime, -1), 'yyyy-MM-dd')`.
5. Click **OK** → **Publish all**.

---

## Part 8 — Verify

1. In ADF Studio, click the **Monitor** icon (left rail) → **Pipeline runs** — you should see your Debug run(s) from step 7e.7.
2. Go to your **Storage account** → **Containers** → `bronze` → `trades/2026-05-01/` — confirm a `.parquet` file exists.
3. Do the same for the `silver` container.
4. Back in the SQL **Query editor**, run: `SELECT COUNT(*) FROM dbo.trade_blotter_silver;` — with just the 10-row seed loaded, expect a smaller number after de-duplication/filtering; with the full 567-row dataset loaded, expect **554**.

You've now built, by hand, exactly what `03_deploy_adf_pipeline.sh` builds in under a minute. Understanding both paths is the point — the script for speed and repeatability, the portal for intuition about what's actually happening underneath.
