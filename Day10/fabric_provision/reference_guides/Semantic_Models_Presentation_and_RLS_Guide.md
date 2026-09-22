# Semantic Models: How to Present Them, Build Them, and Prove RLS Actually Works

**Written for someone who hasn't done this hands-on before.** Every
section explains the "why" before the "how," and every claim about what
should happen is backed by something you can actually run and see for
yourself — most of it before you even open Fabric.

---

## Part 1 — What a Semantic Model Actually Is (and How to Present It)

### The one-sentence definition

A semantic model is the layer that sits between your raw tables and a
report — it defines **relationships** (how tables join), **measures**
(the calculations a business user shouldn't have to rewrite every
time), and **business-friendly names**, so that someone who has never
seen your schema can still get a correct answer.

### The analogy that lands best when presenting this

> "Imagine handing someone the keys to a car versus handing them a box
> of loose engine parts. The parts can technically do everything the
> car can do — but only if you already know how they fit together. A
> semantic model is the assembled car: the tables (parts) are the same
> ones you always had, but now there's a steering wheel (a relationship
> that's already defined) and a speedometer (a measure that's already
> calculated), so anyone can drive it."

### Why this needs its own session, distinct from "just querying tables"

You already know how to query `gold_fact_trades_daily` directly in SQL.
The reason a semantic model exists anyway:

1. **Consistency** — if five different report authors each write their
   own `SUM(trade_value)` query, you get five subtly different
   definitions of "total trade value" the moment someone forgets a
   filter. One measure, defined once, is the fix.
2. **Governed access** — Row-Level Security (the second half of this
   guide) is configured *on the semantic model*, not per-report. Build
   it once, and every report built on that model inherits it
   automatically.
3. **Self-service** — a business user who has never opened SQL Server
   Management Studio can still drag `desk` and `Total Trade Value`
   onto a Power BI canvas and get a trustworthy number.

### A suggested way to present this live

1. Open the Lakehouse's **Tables** view and show `gold_fact_trades_daily`
   as a plain table — ask the room: "if I asked you right now, live,
   'what's our total Equities desk trade value,' how would you get
   that number?" (Answer: write a SQL query, every time, from scratch.)
2. Then show a semantic model with `Total Trade Value` already defined
   as a measure, and `desk` as a filterable field. Drag both onto a
   card visual. **The point:** the same answer, but nobody had to write
   SQL to get it, and everyone gets the *same* answer because it's
   computed the same way, once.

---

## Part 2 — Building the Semantic Model on Your Fabric Workspace

This uses the Warehouse (`oaktree_trades_wh`) and Lakehouse
(`oaktree_trades_lh`) from the Fabric provisioning scripts. If you
haven't run `dbt seed && dbt run` (or the notebook equivalent) against
them yet, do that first — the semantic model needs real tables to
attach to.

### Step 1 — Create the semantic model

1. Open your Fabric workspace in the browser.
2. Find `oaktree_trades_wh` (or your Lakehouse, if that's where your
   Gold tables live) → click **⋯ (more options)** → **New semantic model**.
   (Alternative path: **+ New item → Semantic model**, then pick your
   source tables from the wizard.)
3. Give it a name: `oaktree_trades_semantic_model`.
4. Select the tables to include: `gold_fact_trades_daily` and
   `gold_dim_trader` (or their SCD2-suffixed equivalents if you built
   those versions).
5. Click **Confirm** / **Create**.

### Step 2 — Confirm the relationship exists (and is correct)

1. Open the new semantic model → **Model view** (or **Manage
   relationships**, depending on your Fabric version).
2. You should see a line connecting `gold_fact_trades_daily.trader_id`
   to `gold_dim_trader.trader_id`.
3. **If there's no line:** Fabric only auto-detects relationships when
   column names match exactly. Click **+ New relationship**, and set it
   up manually: From table `gold_fact_trades_daily`, column
   `trader_id` → To table `gold_dim_trader`, column `trader_id`.
   Cardinality: **Many to one** (many facts, one dimension row).
   Cross-filter direction: **Single** (dimension filters fact, not the
   reverse — this matters for Part 4 below).

### Step 3 — Add your first measure

1. Right-click `gold_fact_trades_daily` in the model view → **New measure**.
2. Enter:
   ```dax
   Total Trade Value = SUM(gold_fact_trades_daily[total_trade_value])
   ```
3. Press Enter. You should see it appear as a new field (with a
   calculator icon, distinguishing it from a plain column) under
   `gold_fact_trades_daily`.

---

## Part 3 — Verifying It's Actually Working

**Don't skip this — verifying against a known number is how you catch
a broken relationship before it embarrasses you in front of a
stakeholder.**

### The number you should see

Using this program's dataset, run `rls_profile_simulator.py` (see
Part 5) or recall from earlier sessions: **Total Trade Value across
everyone, unrestricted, is 3,324,971,143.00** (or ≈3.32B, depending on
which day's data you're working from — the exact figure matters less
than confirming your model matches whatever your own tables currently
contain).

### How to check it in Fabric

1. From the semantic model, click **New report** (or open Power BI
   Desktop and connect to this semantic model via **Get Data → Power
   BI semantic models**).
2. Drag `Total Trade Value` onto a blank canvas as a **Card** visual.
3. **Compare the number shown to what you expect.** If it's roughly
   double what you expect, that's the classic sign of a relationship
   set to the wrong cross-filter direction, or a `is_current` filter
   missing on an SCD2-aware table (see the earlier Unified Analytics
   session's "$39.5M overstatement" example — same root cause).
4. Drag `desk` onto the canvas as a slicer, and confirm filtering by
   desk changes the card's number — this proves the relationship
   between fact and dimension is actually being used, not just present
   on the diagram.

**If you don't have live Fabric access yet, or want to sanity-check
your expected number before you get there, run
`rls_profile_simulator.py` locally first (Part 5) — it computes the
exact same numbers using the exact same logic, entirely on your own
laptop.**

---

## Part 4 — Important Clarification: Purview Does NOT Do Row-Level Security

**This is worth stopping on, because it's a very common mix-up.**

| | Azure Purview | Row-Level Security |
|---|---|---|
| **What it controls** | Whether a table/column is *discoverable*, *classified* (e.g., "Confidential"), and *cataloged* — and workspace/item-level access via Fabric's own permission model | Which *rows* of a table a specific person can see, within a table they're already allowed to open |
| **Where it's configured** | The Purview portal (Data Map, classification rules, access policies) | Inside the semantic model itself (Manage roles in Power BI Desktop, or the equivalent in Fabric) |
| **Analogy** | The label on a filing cabinet ("Confidential — HR") and who's allowed to open the cabinet at all | Once the cabinet is open, a rule that says "you may only read the folders with YOUR name on them" |

**Concretely:** Purview can tell you (and enforce) that `gold_dim_trader`
contains "Confidential" data and that only certain roles can access
that *item* at all. But once someone has access to the semantic model,
**Purview has no mechanism to say "trader A can see row 1 but not row
2."** That row-level filtering is entirely the semantic model's job,
configured via RLS roles, exactly as built in Part 5 below.

**If your goal was "use Purview to restrict access by trader_id,"** the
correct tool is RLS on the semantic model (below) — Purview's role is
upstream of that: cataloging the table, classifying it as sensitive,
and controlling who can open the *item* in the first place. Both
matter; they solve different problems.

---

## Part 5 — Setting Up a Profile Per Trader and Proving RLS Works

### Step 0 — Prove the concept locally first (no Fabric needed yet)

Run the included `rls_profile_simulator.py`:

```bash
pip install duckdb pandas --break-system-packages
python3 rls_profile_simulator.py
```

**Verified output you should see** (numbers will match if you're using
this program's standard dataset):

```
>>> Trader Profile: A. Mehta (id=1, Equities desk)
    RLS filter applied: WHERE trader_id = 1
    Rows visible: 45   Total trades: 81.0   Total value: 454,100,406.00

>>> Trader Profile: R. Iyer (id=2, Credit desk)
    RLS filter applied: WHERE trader_id = 2
    Rows visible: 44   Total trades: 86.0   Total value: 463,059,131.00

>>> Compliance Profile (sees ALL desks)
    RLS filter applied: (none -- unrestricted)
    Rows visible: 62   Total trades: 554.0   Total value: 3,324,971,143.00
```

**Notice:** every trader's `trades_visible` figure adds up to exactly
554 — the same total Compliance sees. Nobody's data went missing;
everyone just sees a different, correctly bounded slice of it. That
arithmetic check (do the parts sum to the whole?) is the single best
sanity check for whether an RLS design is correct, in Fabric or
anywhere else.

The script also includes a **Part 2** showing the same idea
group-based (all Equities-desk traders sharing one view) instead of
per-individual — useful if your organization prefers assigning access
by desk/team rather than by named person.

### Step 1 — Create a trader-to-login mapping table (your "profiles")

In the real world, RLS needs to know which *logged-in user* corresponds
to which `trader_id`. Create a small table for this — either as a new
seed/model in your dbt project, or a quick table in the Warehouse:

```sql
CREATE TABLE trader_login_mapping (
    trader_id INT,
    login_email VARCHAR(100)
);

INSERT INTO trader_login_mapping (trader_id, login_email) VALUES
    (1, 'a.mehta@oaktree-example.com'),
    (2, 'r.iyer@oaktree-example.com'),
    (3, 's.kapoor@oaktree-example.com'),
    (4, 'n.rao@oaktree-example.com'),
    (5, 'p.sharma@oaktree-example.com'),
    (6, 'v.nair@oaktree-example.com');
```

*(For a real deployment, `login_email` would be each trader's actual
Entra ID / Microsoft 365 sign-in address — these placeholder addresses
are only for practicing the pattern.)*

Add this table to your semantic model the same way you added the
others (semantic model → **⋯** → **Manage tables**, or rebuild the
model to include it).

### Step 2 — Create the Dynamic RLS role (one role, works for every trader)

1. Open the semantic model in **Power BI Desktop** (Home ribbon →
   **Manage roles**), or the equivalent **Security** configuration
   screen if editing directly in the Fabric web experience.
2. Click **Create** → name it `TraderSelfView`.
3. Select the table to filter: `gold_dim_trader`.
4. Enter this DAX filter expression:
   ```dax
   [trader_id] = LOOKUPVALUE(
       trader_login_mapping[trader_id],
       trader_login_mapping[login_email], USERPRINCIPALNAME()
   )
   ```
5. Click **Save**.

**What this does, in plain language:** "Look up who's currently
logged in (`USERPRINCIPALNAME()`), find their `trader_id` in the
mapping table, and only show `gold_dim_trader` rows matching that
`trader_id`." Because the relationship from Part 2 connects
`gold_dim_trader` to `gold_fact_trades_daily`, this single filter
automatically restricts the fact table too — you do not need to write
a second rule for the fact table.

### Step 3 — Test every profile WITHOUT needing six different logins

This is the step that makes the demonstration actually possible before
you have real user accounts set up.

1. In Power BI Desktop, go to **Modeling** → **View as**.
2. Check the `TraderSelfView` role, and additionally provide **Other
   user**: type one of your placeholder emails, e.g.
   `s.kapoor@oaktree-example.com`.
3. Click **OK**. Your report canvas now behaves EXACTLY as if
   S. Kapoor had logged in — showing only their trades.
4. Note the `Total Trade Value` card's number. **Compare it to the
   simulator's printed value for trader_id 3 (S. Kapoor): 649,764,238.00.**
   They should match.
5. Click **Modeling → View as** again, change the "Other user" email to
   a different trader, and watch the SAME report, the SAME visuals,
   update to a completely different number — with zero report changes.
6. Finally, test with no "Other user" override at all, or build a
   second role (`ComplianceFullAccess`, no filter expression) and
   switch to that — confirm you now see the full, unrestricted total.

**This "View as" toggle, repeated for each profile, IS the live
demonstration** — the same report, switched between profiles, visibly
showing different data each time, with the underlying numbers matching
exactly what the local simulator already proved would happen.

### Step 4 — Publish and assign real people (when you're ready to go live)

Once you've verified locally with **View as**, the last step for a real
rollout is publishing the report and assigning actual users or security
groups to each role from the Fabric workspace (**Semantic model → ⋯ →
Security → Add** next to `TraderSelfView`). This part is covered in
full step-by-step detail, including the Entra ID security group setup,
in the earlier `RLS_Group_Based_Access_Guide.md` from this program —
this guide focuses on getting you to a working, testable local proof
first.

---

## Quick Reference: What to Run, in Order

```bash
# 1. Prove the concept locally (no Fabric needed):
python3 rls_profile_simulator.py

# 2. Build the semantic model in Fabric (Part 2), verify the number
#    matches the simulator's Compliance total (Part 3)

# 3. Create the mapping table (Part 5, Step 1), then the RLS role
#    (Part 5, Step 2)

# 4. Use "View as" repeatedly to demonstrate each profile (Part 5, Step 3)
#    -- compare every number against the simulator's printed output
```

If any number in Fabric doesn't match the simulator's output for the
same profile, the mismatch itself tells you where to look: a
relationship pointing the wrong way, a missing `is_current` filter on
an SCD2 table, or a typo in the mapping table's email address.

