# RLS Across Fabric Layers: Warehouse, OneLake, and Semantic Model

## Answering the Core Question First

**"If RLS is applied at Warehouse level, does it travel through to the
Semantic layer?"**

**Yes, but only conditionally — and there's a real cost when it does.**
Here's the complete picture, verified against current Microsoft
documentation:

| RLS defined at... | Semantic model type | Does it apply? | Notes |
|---|---|---|---|
| **Warehouse** (T-SQL `CREATE SECURITY POLICY`) | DirectQuery | ✅ Yes | The model queries the Warehouse live, every time |
| **Warehouse** (T-SQL) | Direct Lake **on SQL** (via the SQL analytics endpoint) | ✅ Yes | Fabric **automatically falls back to DirectQuery** specifically to honor it — you lose Direct Lake's in-memory speed for affected queries, but the filtering is correct |
| **Warehouse** (T-SQL) | Import | ❌ No | Data is copied ONCE at refresh time using a fixed identity; the security context doesn't exist anymore once the copy is made |
| **Warehouse** (T-SQL) | Direct Lake **on OneLake** (reads Delta files directly, bypassing SQL entirely) | ❌ No | This mode never touches the SQL engine where the predicate lives |
| **Warehouse** (T-SQL) | A Spark notebook, or anyone with direct Lakehouse/OneLake file access | ❌ No | T-SQL security policies only guard the SQL engine — they do not protect the same underlying Delta files reached a different way |
| **OneLake Security roles** (defined on the Lakehouse) | Direct Lake (either flavor) | ✅ Yes | This is the mechanism *designed* to be engine-agnostic |
| **OneLake Security roles** | Spark notebooks | ✅ Yes | Spark reads the same precomputed "effective access" OneLake calculates for each user |
| **OneLake Security roles** | SQL analytics endpoint | ✅ Yes — **but only if** the endpoint is switched to **"User's identity"** mode (Security tab) | Left on its default/fixed identity mode, the endpoint ignores OneLake security roles entirely |
| **Semantic model** (Power BI "Manage roles") | Only that one semantic model | N/A | Never flows down to the Warehouse, Lakehouse, Spark, or any other consumer — this is the narrowest-scoped option |

### The direct answer to "how do I apply it once, at the Warehouse, and have it work everywhere without reapplying?"

**You can't — not starting from the Warehouse.** T-SQL RLS is
fundamentally scoped to the SQL engine; it structurally cannot reach
Spark or Direct-Lake-on-OneLake consumers, because those paths never
execute a SQL query at all.

**The mechanism actually designed to solve this is OneLake Security —
defined once on the Lakehouse, not the Warehouse.** Microsoft's own
stated positioning: *"OneLake Security is the recommended approach for
consistent data protection across all engines."* Part 3 of this guide
walks through configuring it.

### One universal exception, regardless of which layer you choose

**Workspace Admins, Members, and Contributors bypass RLS/OneLake
security entirely** — these controls only restrict the **Viewer** role
(or users explicitly assigned to a OneLake security role). If someone
has elevated workspace access, or can reach the data directly through
Spark with a ReadAll-style permission, no amount of Warehouse or
OneLake RLS configuration will hide anything from them. This is the
same least-privilege principle from earlier sessions in this
program — RLS is a report-consumption control, not a substitute for
correctly scoped workspace roles.

---

## Part 0 — Prove the Concept Locally, Before Touching Fabric

Run `live_vs_frozen_rls_demo.py` first. It doesn't just describe the
propagation behavior above — it **runs both scenarios with real code**
and shows you the actual, different numbers:

```bash
cd local_demo
python3 live_vs_frozen_rls_demo.py
```

**What you'll see (verified output):**

```
PART 1 -- LIVE QUERY MODE (DirectQuery / Direct Lake on SQL)
>>> Trader 1 (A. Mehta) asks
    Result: 81 trades, 454,100,406.00 total value
>>> Trader 3 (S. Kapoor) asks
    Result: 99 trades, 649,764,238.00 total value
>>> Compliance asks
    Result: 554 trades, 3,324,971,143.00 total value

PART 2 -- IMPORT MODE
>>> Trader 1 (A. Mehta) opens the report built on this IMPORTED model:
    Sees: 554 trades, 3,324,971,143.00 total value  <-- SAME as everyone else
>>> Trader 3 (S. Kapoor) opens the SAME report:
    Sees: 554 trades, 3,324,971,143.00 total value  <-- IDENTICAL, not filtered
```

**This is the whole propagation question, made concrete:** the "live"
path re-evaluates who's asking on every query; the "frozen" path baked
in one answer, for one identity, at refresh time, and has nothing else
to give afterward. Use this script live in your session as the
opening demo — it needs no Fabric access at all, and it sets up
everyone's intuition correctly before the real portal work begins.

---

## Part 1 — Implementing RLS at the Warehouse Level

Uses `01_warehouse_rls_setup.sql` (provided alongside this guide),
against `oaktree_trades_wh` and its `gold_fact_trades_daily` /
`gold_dim_trader` tables.

### Step 1 — Run the setup script

1. Open the Warehouse in the Fabric portal → **New SQL query**.
2. Paste in the full contents of `01_warehouse_rls_setup.sql` and run it.
3. Confirm no errors — you should now have: a `Security` schema, a
   `trader_login_mapping` table, a predicate function, and an active
   security policy.

### Step 2 — Verify the policy is active

```sql
SELECT * FROM sys.security_policies;
SELECT * FROM sys.security_predicates;
```

Both should return one row referencing `TraderRowFilter`.

### Step 3 — Test with a real second identity

Unlike the earlier semantic-model RLS session (where Power BI's **View
as** feature let you simulate any user from one login), **T-SQL RLS is
enforced by the database engine itself** — there's no equivalent
"pretend to be someone else" trick from a single elevated connection.
To actually see a different result, you need a second real login:

1. Add a colleague, or a second test Entra ID account you control, to
   the Warehouse (or workspace) with read access.
2. Update `Security.trader_login_mapping` to include that account's
   real login name against a specific `trader_id`.
3. Have that second account connect (via the SQL analytics endpoint,
   SSMS, or Azure Data Studio) and run the same `SELECT` from the
   script — confirm they see only their assigned trader's rows, while
   your own (admin) connection still sees everything.

---

## Part 2 — Building a Direct Lake Model on Top, and Watching the Fallback Happen

### Step 1 — Build the semantic model

Follow the same steps as the earlier Unified Analytics session: **New
semantic model** on `oaktree_trades_wh`, selecting
`gold_fact_trades_daily` and `gold_dim_trader`.

### Step 2 — Confirm it's actually falling back to DirectQuery for RLS'd tables

1. In the semantic model's settings, find **Direct Lake behavior** (in
   the Model settings / Semantic model settings pane).
2. If it's set to **Automatic** (the default), Fabric silently
   downgrades affected queries to DirectQuery to honor the Warehouse's
   RLS — which is exactly what you want here, and requires no extra
   configuration from you.
3. **To prove this is actually happening (not just trust the
   documentation):** open a DAX query view and run:
   ```dax
   EVALUATE TABLETRAITS()
   ```
   This surfaces whether the engine is treating the table as Direct
   Lake-eligible or has fallen back — a table affected by RLS should
   show fallback behavior here.
4. **Alternative verification:** open the **Fabric Capacity Metrics
   app** and look at query-level details for this semantic model —
   queries against the RLS'd tables should show as DirectQuery
   operations, not Direct Lake reads.
5. **A instructive (optional) experiment for the session:** temporarily
   force **Direct Lake Only** in the model's Direct Lake behavior
   setting, then try to refresh. **This refresh will fail** — Fabric
   won't let you force pure Direct Lake mode on a table an active
   security policy protects, since there's no way to enforce the
   predicate without falling back. Reverting to **Automatic** (or
   **Direct Lake with DirectQuery fallback**) fixes it immediately —
   a very visible, hard-to-misunderstand demonstration of the
   propagation actually being enforced, not just theoretical.

---

## Part 3 — OneLake Security: Define Once, Apply Everywhere

This is the actual answer to "how do I do this once and never
reapply." Configured on the **Lakehouse**, not the Warehouse.

### Prerequisites

- Your Lakehouse must be **schema-enabled** for full support.
- You'll assign Entra ID security groups (not individual users) to
  roles — create these in Entra ID first if you haven't already (see
  the earlier `RLS_Group_Based_Access_Guide.md` for that setup).
- **Important, one-way decision:** once you turn on OneLake security
  for an item, **you cannot turn it back off.** Don't enable this on a
  whim during a live demo unless you're using a disposable practice
  Lakehouse.

### Step 1 — Enable OneLake security

1. Open `oaktree_trades_lh` in the Fabric portal.
2. Select **Manage OneLake security**.
3. Confirm the enablement prompt. A `DefaultReader` role is
   automatically created, granting existing ReadAll users full access —
   this exists specifically so enabling this feature doesn't instantly
   lock out everyone who already had access.

### Step 2 — Create a role per desk (or per trader, if you prefer Dynamic-style)

1. Click **New** to create a role — name it `EquitiesDeskReaders`.
2. Under **Members**, add the `OakTree-Equities-Desk` Entra ID security
   group (from the earlier group-based RLS guide).
3. Grant **Read** access to the tables this role should see:
   `gold_fact_trades_daily`, `gold_dim_trader`.

### Step 3 — Define the row-level rule

1. Next to `gold_dim_trader` in this role, select **more options (...)**
   → **Row security**.
2. In the code editor, enter the row filter (note the exact required
   form — a full `SELECT` statement, up to 1000 characters):
   ```sql
   SELECT * FROM dbo.gold_dim_trader WHERE desk = 'Equities'
   ```
3. **Save.**
4. Repeat for `gold_fact_trades_daily` if it also needs a direct
   row rule — or rely on the relationship to `gold_dim_trader`
   propagating the restriction, exactly like the semantic-model RLS
   pattern from the earlier session.

### Step 4 — Enable enforcement on the SQL analytics endpoint (the easy-to-forget step)

1. Open the Lakehouse's **SQL analytics endpoint**.
2. Go to **Security** (or workspace settings for the endpoint) and
   switch identity mode from the default to **User's identity**.
3. **Without this step, the SQL analytics endpoint keeps using its
   prior fixed-identity behavior and silently ignores your new OneLake
   security roles** — this is the single most common reason someone
   configures OneLake security correctly and then wonders why nothing
   changed when they query via SQL.

### Step 5 — Verify it works across THREE different engines, with zero extra configuration

This is the actual "define once, see it everywhere" proof:

1. **SQL analytics endpoint:** connect as a member of the Equities desk
   group, run `SELECT * FROM gold_dim_trader` — confirm only Equities
   rows return.
2. **Spark notebook:** attach a notebook to the same Lakehouse, run
   `spark.read.table("gold_dim_trader").show()` as the same user —
   confirm the identical restriction applies, with no notebook-specific
   security code written at all.
3. **Direct Lake semantic model:** build (or reuse) a semantic model on
   this Lakehouse, and confirm a report opened by an Equities-desk
   group member shows only Equities data — again, no RLS role defined
   inside the semantic model itself.

**If all three show the same restricted view, you've just demonstrated
the entire point of this session:** one rule, three engines, zero
reapplication.

---

## Part 4 — Recap: Semantic-Model-Level RLS (the Narrowest Option)

Already covered in depth in the earlier Unified Analytics session
(`Semantic_Models_Presentation_and_RLS_Guide.md`) — included here only
for completeness of the comparison:

- Defined via **Manage roles** directly in the semantic model
- Applies **only within that one model** — never flows to the
  Warehouse, Lakehouse, Spark, or any other semantic model built on the
  same tables
- The right choice when: you're specifically in **Import mode** (where
  neither Warehouse RLS nor OneLake security can reach you), or you
  need a rule that's genuinely specific to one report and shouldn't
  apply anywhere else

---

## Decision Guide: Which Layer Should You Actually Use?

| Your situation | Recommended layer |
|---|---|
| Multiple engines (Spark + SQL + Power BI) all need the same restriction | **OneLake Security** — the only mechanism that reaches all three |
| You're SQL-first, only ever query via the Warehouse/DirectQuery, never Spark | **Warehouse RLS** is simpler to reason about and sufficient |
| Your semantic model is Import mode | You have no choice — **semantic-model RLS**, since neither of the above reaches an imported copy |
| A rule genuinely belongs to one specific report only | **Semantic-model RLS**, deliberately — don't over-centralize a one-off rule |
| You want Direct Lake's full in-memory performance AND row security | **OneLake Security** — unlike Warehouse RLS, it doesn't force a DirectQuery fallback |

---

## Files in This Package

- `local_demo/live_vs_frozen_rls_demo.py` — run this first, needs no Fabric access
- `tsql/01_warehouse_rls_setup.sql` — Warehouse-level RLS, ready to run against `oaktree_trades_wh`
- This guide

## A Note on What's Been Verified vs. What Requires Your Own Fabric Session

The propagation behavior in the table at the top of this guide, the
T-SQL syntax, and the OneLake security portal steps are all confirmed
against current Microsoft documentation as of this writing. The local
Python demo's numbers are genuinely executed and verified. What I
cannot verify from outside a live Fabric tenant: the exact current
wording of every portal button (Microsoft iterates the UI
frequently) and capacity-specific behavior (e.g., whether a given
trial/F-SKU capacity has all OneLake security features fully rolled
out). Budget a few minutes before your session to click through Parts
2 and 3 once yourself, so any small UI drift doesn't surprise you live.
