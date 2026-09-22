# Capstone Lab: End-to-End Fabric Pipeline via the Azure Portal

**This is the final session of the program.** Every step below is
something you've already done once, in isolation, in an earlier
session — today's job is doing all of them in sequence, on one
workspace, so you see the whole platform work together as one thing
instead of ten separate exercises.

**Format:** pure lab. Work through this at your own pace, in teams of
4-5. A facilitator is available for questions, not lectures.

---

## Before You Start: What You're Building

```
Fabric Capacity (F2, Sweden Central)
        │
        ▼
   Workspace ──────────────┬───────────────┐
        │                  │               │
        ▼                  ▼               ▼
   Lakehouse          Warehouse      Semantic Model
   (Bronze Files,     (dbt-ready,    (built on the
    Silver/Gold        RLS via        Gold tables,
    Delta Tables)       T-SQL)         with RLS)
        │
        ▼
   Notebook (Bronze → Silver → Gold, SCD2 at Gold)
```

By the end of today, you will have: a Fabric capacity and workspace
you provisioned yourself; sample data uploaded and transformed through
all three Medallion layers; an SCD2-aware dimension with genuine,
provable history; a queryable semantic model; and Row-Level Security
enforced and demonstrated at at least one layer of your choosing.

**Two ways to get there — pick one, or do both and compare:**
- **Path A (this document):** click through the Azure/Fabric portal
  yourself, step by step
- **Path B:** run the automation scripts (`scripts/run_all.sh`) and
  use this document only to verify what the script did

---

## Part 1 — Provision the Fabric Capacity

1. Go to [portal.azure.com](https://portal.azure.com) and sign in.
2. Search **"Microsoft Fabric"** in the top search bar → **+ Create**
   (or search directly for **"Fabric capacity"**).
3. **Subscription / Resource group:** create a new resource group,
   e.g. `rg-oaktreecapstone-<yourname>`.
4. **Capacity name:** `cap<yourname>capstone` (lowercase, no hyphens).
5. **Region:** **Sweden Central**.
6. **Size:** **F2** — this is a real, billed SKU, not the earlier free
   trial capacity. See the cost note at the end of this guide.
7. **Administrator:** add yourself.
8. **Review + create.** Wait for deployment (typically 2-5 minutes).

**Verify:** the capacity's **Overview** page shows **State: Active**.

---

## Part 2 — Create the Workspace, Assigned to Your Capacity

1. Go to [app.fabric.microsoft.com](https://app.fabric.microsoft.com).
2. **Workspaces** (left nav) → **+ New workspace**.
3. Name: `ws-oaktreecapstone-<yourname>`.
4. Under **Advanced** → **License mode**, select the capacity you just
   created (not Trial or Pro — your paid F2 capacity should appear in
   this list once Part 1 finished).
5. **Apply.**

**Verify:** the workspace's settings

---

## Part 3 — Create the Lakehouse

1. Inside the new workspace: **+ New item → Lakehouse**.
2. Name: `oaktree_trades_lh`.
3. Wait for it to open — you'll see empty **Files** and **Tables** sections.

**Verify:** the Lakehouse explorer loads with both sections visible
and empty.

---

## Part 4 — Create the Warehouse

1. Inside the same workspace: **+ New item → Warehouse**.
2. Name: `oaktree_trades_wh`.
3. Once created, go to **Settings → Connection strings** and copy the
   SQL connection string — you'll need it later if you configure dbt
   or T-SQL RLS against this Warehouse.

**Verify:** the Warehouse opens to an empty **New SQL query** editor.

---

## Part 5 — Upload the Sample Data

1. In the Lakehouse (`oaktree_trades_lh`) → **Files** → **...** → **New
   subfolder** → name it `bronze`.
2. Open the `bronze` folder → **Upload → Upload files**.
3. Select all 4 files from this package's `data/` folder:
   `trade_blotter.csv`, `dim_trader.csv`,
   `dim_trader_snapshot_20260601.csv`, `dim_trader_snapshot_20260901.csv`.

**Verify:** all 4 files appear under `Files/bronze/`.

---

## Part 6 — Import and Run the Pipeline Notebook

1. In the workspace: **+ New item → Import notebook** → select
   `notebook/fabric_intro_etl_notebook.py` from this package.
   (Fabric recognizes the `# Fabric notebook source` header and
   reconstructs proper cells and markdown automatically.)
2. Open the imported notebook → **Add Lakehouse** (left panel) →
   **Existing Lakehouse** → select `oaktree_trades_lh`.
3. Confirm a Spark session starts (top of the notebook) — first start
   takes 2-3 minutes.
4. Fill in the widget/parameter values at the top: your storage
   details if prompted, and `SNAPSHOT_DATE = "2026-06-01"`.
5. **Run all.**

**Verify — this is the most important checkpoint in the whole
session:**

| Check | Expected Result |
|---|---|
| `silver_trades` row count | 554 |
| `gold_fact_trades_daily` row count | 290 |
| `gold_dim_trader_scd2` row count | 10 (started at 6, 4 traders changed/added) |
| Point-in-time query for trader_id 4 | Two rows: Macro (expired) and Credit (current) |

If any of these don't match, **stop and debug here** before moving
on — every later part of this lab depends on this data being correct.

---

## Part 7 — Build the Semantic Model

1. From `oaktree_trades_wh` (or the Lakehouse) → **⋯ → New semantic model**.
2. Select `gold_fact_trades_daily` and `gold_dim_trader_scd2`.
3. Confirm the relationship: `gold_fact_trades_daily.trader_id` →
   `gold_dim_trader_scd2.trader_id`, **Many to one**, single
   cross-filter direction.
4. Add a measure:
   ```dax
   Total Trade Value (Current) =
       CALCULATE(SUM(gold_fact_trades_daily[total_trade_value]))
   ```
5. **New report** → drag the measure onto a card visual, `desk` onto a
   slicer → confirm filtering works and the unfiltered total is
   **3,324,971,143.00** (or matches your own data's current total).

*(Full walkthrough with the "$39.5M overstatement" pitfall example:
`reference_guides/Semantic_Models_Presentation_and_RLS_Guide.md`.)*

---

## Part 8 — Implement RLS (Choose Your Layer)

**This is the open-ended part of the lab — decide as a team which
layer to implement, based on what you'd actually recommend to OakTree,
then be ready to justify the choice.**

- **Option A — Warehouse T-SQL RLS:** run
  `tsql/01_warehouse_rls_setup.sql` against `oaktree_trades_wh`.
  Fastest to implement; only protects SQL/DirectQuery access.
- **Option B — OneLake Security:** on `oaktree_trades_lh` → **Manage
  OneLake security** → create a role per desk, define row security.
  More setup; protects Spark, SQL endpoint, AND Direct Lake
  consistently, with zero reapplication.
- **Option C — Semantic-model RLS:** **Manage roles** in your Part 7
  model directly. Narrowest scope; only protects that one model.

**Demonstrate it working:** use **View as** (Option C) or a second
test login (Options A/B) to show two different profiles seeing
different data from the same query/report.

*(Full decision guide and step-by-step for all three:
`reference_guides/RLS_Across_Fabric_Layers_Guide.md`. Run
`reference_guides/live_vs_frozen_rls_demo.py` first if you want to see
the propagation concept proven locally before touching the portal.)*

---

## Part 9 — Governance Touchpoint (Purview)

You're not expected to fully configure Purview in this lab — this part
is a guided discussion, not a build step:

1. If your organization has Purview access, register the workspace as
   a source (**Data Map → Sources → Register → Microsoft Fabric**).
2. Open the **Lineage** view for `gold_dim_trader_scd2` and trace it
   back through the notebook to `Files/bronze/dim_trader.csv`.
3. Discuss as a team: which columns in today's tables would you
   classify as Confidential, and why? (Reference the classification
   table from the earlier Governance session for a worked example.)

---

## Final Checklist

- [ ] Fabric capacity: **Active**
- [ ] Workspace assigned to the capacity
- [ ] Lakehouse + Warehouse both created
- [ ] 4 sample files uploaded to `Files/bronze/`
- [ ] Notebook run completed; Silver = 554, Gold fact = 290, Gold SCD2 dimension = 10
- [ ] Semantic model built, relationship confirmed, measure returns the correct total
- [ ] RLS implemented at (at least) one layer, and demonstrated with two different profiles seeing different data
- [ ] Team can explain: why did you pick that RLS layer over the other two?

---

## Cost Note

**F2 is a real, continuously-billed Azure resource** — not the free
trial capacity used in earlier sessions. At the end of the lab:

```bash
az fabric capacity suspend --resource-group <rg> --capacity-name <name>
```

Or delete the resource group entirely if you're finished with the
exercise for good.
