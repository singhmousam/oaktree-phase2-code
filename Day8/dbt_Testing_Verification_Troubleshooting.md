# dbt Local Testing, Verification & Troubleshooting Guide

Three questions, answered with real, reproduced examples against this
program's own dbt project — not generic dbt documentation.

---

## Part 1 — The Simplest Way to Verify Table Content

You don't need DBeaver, Azure Data Studio, or any external tool to look
at what dbt built. dbt has this built in.

### Option A (simplest): `dbt show`

```bash
dbt show --select silver_trades --limit 5
```

This actually runs and prints a preview, directly in your terminal:

```
Previewing node 'silver_trades':
| trade_id | trade_date | security_id | trader_id | trade_type | quantity | ... |
| -------- | ---------- | ----------- | --------- | ---------- | -------- | --- |
|   100001 | 2026-05-01 |           2 |         1 | SELL       |    1,600 | ... |
|   100035 | 2026-05-04 |           3 |         3 | SELL       |   73,000 | ... |
```

### Option B — `dbt show --inline` for a targeted question

Want to check one specific row instead of the first N? Pass any SQL
directly, using `{{ ref(...) }}` exactly like inside a model file:

```bash
dbt show --inline "select * from {{ ref('silver_trades') }} where trade_id = 100224"
```

```
Previewing inline node:
| trade_id | trade_date | security_id | trader_id | trade_type | quantity | ... |
| -------- | ---------- | ----------- | --------- | ---------- | -------- | --- |
|   100224 | 2026-05-19 |           1 |         6 | SELL       |      500 | ... |
```

This is the fastest way to answer "did my change actually make it into
the table?" — no separate SQL client, no connection string.

### Option C — Query the DuckDB file directly with Python

If you want something more exploratory (multiple queries, pandas
DataFrames, filtering), the project's `.duckdb` file is just a regular
file you can open independently of dbt, even while dbt isn't running:

```python
import duckdb
con = duckdb.connect("oaktree_local.duckdb")
print(con.execute("SELECT * FROM main.silver_trades LIMIT 5").fetchdf())
print(con.execute("SELECT COUNT(*) FROM main.gold_fact_trades_daily").fetchone())
```

### Option D — The DuckDB CLI (if you prefer a terminal SQL prompt)

```bash
pip install duckdb --break-system-packages   # if not already installed
duckdb oaktree_local.duckdb
```

```sql
SHOW TABLES;
SELECT * FROM silver_trades LIMIT 5;
.quit
```

**Recommendation: use `dbt show` for day-to-day verification** (Option A/B)
— it requires nothing beyond dbt itself, and it's what you'll reach for
most often. Reach for Option C/D only when you want to explore more
freely (joins across tables, aggregations, charts in a notebook).

---

### The testing sequence to follow

```bash
dbt seed   # reload the CSV -> the raw seed table now has "SEL"
dbt run    # rebuild every model, including silver_trades, from the new data
dbt test   # NOW check the freshly-rebuilt tables
```

### The simplest fix: use `dbt build` instead of separate commands

```bash
dbt build
```

`dbt build` runs seeds, models (in dependency order), snapshots, AND
tests together, correctly ordered, in one command. **This is the
single safest command to reach for after any data change** — it makes
the "forgot to re-run" mistake structurally impossible, because there's
no separate step to forget.

One important behavior to know: **`dbt build` stops building anything
downstream of a failed test.** If your Bronze-layer test fails,
`dbt build` will `SKIP` Silver and Gold rather than build them on top
of data it just told you is suspect. This is intentional — it's the
same "fail fast, don't propagate bad data forward" principle from
Day 1's security-by-design lifecycle, just enforced automatically. If
you want models to build regardless of test outcomes (for exploration),
run `dbt run` and `dbt test` as separate commands instead.

### A second, sneakier cause worth knowing about

If your edited row happens to share a `trade_id` with another row (this
dataset intentionally contains ~8 duplicate `trade_id`s, simulating
retried loads), and your edit landed on the row that ISN'T selected as
"latest" by the `ROW_NUMBER() ... ORDER BY last_modified_ts DESC`
de-duplication logic in `silver_trades.sql`, **your edit gets silently
discarded during de-duplication** — it never reaches the table being
tested at all. Always pick a `trade_id` that appears exactly once in
the seed file when testing an edit like this (or check with
`dbt show --inline "select trade_id, count(*) from {{ ref('trade_blotter') }} group by trade_id having count(*) > 1"`
to see which ones are duplicated first).

### Seeing exactly which rows failed, not just the count

```bash
dbt test --select accepted_values_silver_trades_trade_type__BUY__SELL --store-failures
```

dbt writes the failing rows into a real table you can query:

```python
import duckdb
con = duckdb.connect("oaktree_local.duckdb")
print(con.execute(
    "SELECT * FROM main_dbt_test__audit.accepted_values_silver_trades_trade_type__buy__sell"
).fetchdf())
```

```
  value_field  n_records
0         SEL          1
```

---

## Part 3 — Adding a Test: Quantity and Price Must Always Be Greater Than Zero

Two versions of essentially the same test, deliberately placed at two
different layers, to make an important point about WHERE you test.

### Version A — a reusable generic test (works on any column, any model)

dbt doesn't ship a built-in "greater than zero" test — the popular
`dbt_utils` package adds one (`dbt_utils.expression_is_true`), but here
is a small, dependency-free version you can add to any project without
running `dbt deps`:

**`macros/test_positive_value.sql`**
```sql
{% test positive_value(model, column_name) %}

select *
from {{ model }}
where {{ column_name }} <= 0

{% endtest %}
```

**Usage in `models/schema.yml`:**
```yaml
- name: silver_trades
  columns:
    - name: quantity
      tests:
        - positive_value
    - name: price
      tests:
        - positive_value
```

**Result on Silver — PASSES, as expected:**
```
7 of 11 PASS positive_value_silver_trades_price ... [PASS in 0.05s]
7 of 11 PASS positive_value_silver_trades_quantity ... [PASS in 0.03s]
```

**Why it passes:** `silver_trades.sql`'s own `WHERE quantity > 0 AND
price > 0` clause already removes bad rows during transformation. This
test isn't catching anything new here — it's a **safety net**: if
someone edits the model later and accidentally removes or weakens that
filter, this test starts failing immediately instead of the problem
going unnoticed.

### Version B — the same idea, deliberately placed where it SHOULD fail

**`tests/assert_bronze_trades_positive_quantity_and_price.sql`**
(a singular test — just a SELECT statement; any rows returned = failures)
```sql
select *
from {{ ref('stg_trade_blotter') }}
where quantity <= 0 or price <= 0
```

**Result on Bronze — FAILS, as expected:**
```
1 of 1 FAIL 5 assert_bronze_trades_positive_quantity_and_price ... [FAIL 5 in 0.03s]
[ERROR]: Got 5 results, configured to fail if != 0
```

**Why it fails, correctly:** Bronze is supposed to be a faithful,
unfiltered copy of the source. This dataset's generator intentionally
includes 5 bad records (negative quantity or zero price) to simulate
real data-entry errors — the same 5 records referenced since Day 1 of
this program. A failing test here is Bronze doing its job: telling you
honestly what the source actually sent, before Silver quietly cleans it
up.

**The lesson:** the same logical check can be a genuine bug-catcher at
one layer and a pure safety-net at another. Where you put a test is as
much a design decision as what the test checks.

---

## Quick Reference: Commands Used in This Guide

| Command | What It Does |
|---|---|
| `dbt show --select <model> --limit N` | Preview a model's output without an external SQL tool |
| `dbt show --inline "<sql>"` | Run an arbitrary query using `ref()`, print the result |
| `dbt seed` | Reload seed CSVs into tables — required after ANY seed file edit |
| `dbt run` | Rebuild models — required after any upstream change, since tables don't auto-refresh |
| `dbt test` | Run all (or `--select`ed) tests against the CURRENT state of the database |
| `dbt build` | Seed + run + snapshot + test, in dependency order, in one command — the safest default |
| `dbt test --store-failures` | Write failing rows to a real table you can query afterward |
