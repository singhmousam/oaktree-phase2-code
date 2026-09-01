# Day 3 — Building the Databricks Environment from the Azure Portal (No Scripts)

This document walks through everything `01_provision_databricks.sh`
automates, but by clicking through the Azure Portal and the Databricks
workspace UI instead. Use this if your training environment restricts
CLI access, or if you simply want to see each piece being created.

> **Prerequisite:** Complete Day 2 first (or at least Part 1-6 of
> `Day2_Azure_Portal_StepByStep.md`) — you need the ADLS Gen2 storage
> account and its access key from that environment.

---

## Part 1 — Create the Azure Databricks Workspace

*(Replaces: `01_provision_databricks.sh`, steps 1-2)*

1. In the [Azure Portal](https://portal.azure.com) search bar, type **"Azure Databricks"** → **+ Create**.
2. Resource group: reuse the same `rg-oaktreelab-<yourname>` from Day 2.
3. Workspace name: `dbw-oaktreelab-<yourname>`.
4. Region: the same region as your Day 2 resources.
5. Pricing tier: **Standard** (cheapest tier; sufficient for this lab — Premium adds features like fine-grained access control you don't need today).
6. Click **Review + create** → **Create**. This takes a few minutes longer than most resources — Databricks provisions a managed resource group behind the scenes.
7. Once deployed, click **Go to resource** → **Launch Workspace**. This opens the Databricks workspace UI in a new tab and signs you in via Azure AD automatically (no separate Databricks account needed).

---

## Part 2 — Create a Cluster

*(Replaces: `01_provision_databricks.sh`, step 3)*

1. In the Databricks workspace UI, click **Compute** in the left sidebar → **Create compute**.
2. Cluster name: `day3-training-cluster`.
3. Policy: **Unrestricted** (or your organization's training policy if one exists).
4. Databricks Runtime Version: choose a recent **LTS** version (e.g., `14.3 LTS`) — matches the local practice PySpark version closely enough that behavior is consistent.
5. Node type: **Standard_DS3_v2** (a small, inexpensive VM size — plenty for this dataset's size).
6. Workers: set **Min workers = 2, Max workers = 2** (fixed size, avoids autoscaling surprises during a live demo).
7. Under **Advanced options → Autopilot Options**, confirm **Terminate after 30 minutes of inactivity** is checked — this is your safety net against forgetting to shut it down.
8. Click **Create compute**. It takes roughly 4-6 minutes to reach "Running" — a good moment for a short break or Q&A while it starts.

---

## Part 3 — Upload the Dimension CSVs to DBFS

*(Needed for the broadcast join demo in Notebook 2 — the local practice scripts read these from disk; on Databricks, they need to be somewhere the cluster can see.)*

1. In the Databricks workspace, click **Data** in the left sidebar (or **Catalog**, depending on your workspace's UI version) → look for an **Add data** / **Upload File** option — on Standard-tier workspaces without Unity Catalog this is usually under **Data → Create Table → Upload File**, or **File → Upload data** from a notebook's file menu.
2. Upload `dim_security.csv` and `dim_trader.csv` from the lab's `data/` folder.
3. Note the destination path shown after upload — it will typically be under `/FileStore/tables/`. If your workspace names it differently, note the actual path and adjust the notebook cells accordingly (the notebooks assume `/FileStore/tables/dim_security.csv` and `/FileStore/tables/dim_trader.csv`).

*(Alternative if your workspace doesn't expose a UI upload option: open a new notebook, attach it to your cluster, and run `dbutils.fs.cp("file:/path/to/local/file", "dbfs:/FileStore/tables/dim_security.csv")` after uploading via the notebook's own file-attach feature — every Databricks workspace supports at least one of these two paths.)*

---

## Part 4 — Import the Notebooks

*(Replaces: `01_provision_databricks.sh`, step 4)*

1. In the workspace sidebar, click **Workspace** → navigate to (or create) a folder: right-click **Shared** → **Create → Folder** → name it `Day3`.
2. Right-click the new `Day3` folder → **Import**.
3. In the Import dialog, choose **File** and select `01_bronze_to_silver.py` from `databricks_notebooks/` on your computer. Format: **Source File** (Databricks auto-detects the `# Databricks notebook source` header and reconstructs proper cells).
4. Click **Import**. Repeat for all five notebooks: `01_bronze_to_silver`, `02_distributed_processing_demo`, `03_gold_aggregation`, `04_lab_exercise_STARTER`, `05_lab_solution_REFERENCE`.
   *(Tip: the Import dialog usually accepts multiple files at once — select all five in the file picker if your browser allows it.)*

---

## Part 5 — Run Notebook 1: Bronze to Silver

1. Open `/Shared/Day3/01_bronze_to_silver`.
2. At the top, click **Connect** (or the cluster dropdown) → select `day3-training-cluster`. Wait for it to show attached (a green circle).
3. Run the first cell (the widgets cell) — this creates three input boxes at the top of the notebook: `storage_account_name`, `storage_account_key`, `window_date`.
4. Fill in the widgets:
   - `storage_account_name`: your Day 2 storage account name (e.g., `stoaktreelabdatayourname`)
   - `storage_account_key`: go to your **Storage account** in the Azure Portal → **Access keys** (left menu) → **Show** → copy **key1**
   - `window_date`: `2026-05-01` (or any date you loaded Day 2 data for)
5. Click **Run all** (top right). Watch each cell execute — note the `display()` outputs render as interactive tables directly in the notebook.
6. Confirm the printed `SILVER row count` — for a day with the full sample loaded, this should read **554** minus however many rows fall on that specific date (check against the row count your Day 2 stored procedure reported for the same date).

---

## Part 6 — Run Notebook 2: Distributed Processing Concepts

1. Open `/Shared/Day3/02_distributed_processing_demo`, attach the same cluster.
2. Fill in the same three widgets as Notebook 1.
3. Run all cells.
4. **Look at the real Spark UI:** click the **Spark UI** link (usually found under the cluster's detail page, or via **View → Spark UI** from the notebook) → find the job corresponding to the `groupBy` cell → click into its **SQL / DataFrame** tab → find the `Exchange` node in the diagram. This is the shuffle made visible — something the local practice version can only describe, not show at real multi-executor scale.

---

## Part 7 — Run Notebook 3: Gold Aggregation

1. Open `/Shared/Day3/03_gold_aggregation`, attach the cluster, fill in widgets, **Run all**.
2. After it finishes, open a **new** notebook cell (or a fresh notebook) and run:
   ```sql
   %sql
   SELECT * FROM gold_trades_daily ORDER BY total_trade_value DESC LIMIT 10;
   ```
   This confirms the table registered by Notebook 3's `saveAsTable` call is queryable with plain SQL — the exact preview of Day 6's semantic layer thinking.

---

## Part 8 — The Hands-On Lab (Notebooks 4 and 5)

1. Open `/Shared/Day3/04_lab_exercise_STARTER`, attach the cluster, fill in the widgets.
2. Work through the four TODO cells as a team — this is the same exercise as the local practice version, just running against real cluster-scale data.
3. Only after a genuine attempt, open `/Shared/Day3/05_lab_solution_REFERENCE` to compare.

---

## Part 9 — Shut Everything Down

*(Replaces: `99_teardown_databricks.sh`)*

1. **Compute** (left sidebar) → find `day3-training-cluster` → click the **⋮** menu → **Terminate** (this stops DBU billing immediately; you don't need to delete the cluster definition itself if you plan to reuse it).
2. If you're fully done with Databricks for the program, delete the whole workspace: go to the Azure Portal → your `dbw-oaktreelab-<yourname>` resource → **Delete**.
3. Remember Day 2's resources (SQL DB, Storage, Key Vault, ADF) are separate — tear those down independently via `Day2_Azure_Portal_StepByStep.md`'s guidance or `day2_lab/scripts/99_teardown.sh` when the whole program is finished, since Day 4 onward still reads from that storage account.

---

## Quick Troubleshooting

| Symptom | Likely Cause | Fix |
|---|---|---|
| `Test connection` or notebook read fails with a 403/authorization error | Storage account key copied incorrectly, or the container name is wrong | Re-copy **key1** exactly from **Access keys**; confirm the container is `bronze` or `silver` (lowercase) |
| Cluster stuck on "Pending" for a long time | Region capacity constraints for the chosen VM size | Try a different node type (e.g., `Standard_DS3_v2` → `Standard_D4s_v3`) or a different region |
| `/FileStore/tables/dim_security.csv` not found | Upload landed at a different DBFS path | Check the path shown after upload in Part 3, adjust the `spark.read.csv(...)` path in the notebook to match |
| Notebook widgets don't appear | The first cell wasn't run yet | Run the top cell (containing `dbutils.widgets.text(...)`) before trying to fill in values |
