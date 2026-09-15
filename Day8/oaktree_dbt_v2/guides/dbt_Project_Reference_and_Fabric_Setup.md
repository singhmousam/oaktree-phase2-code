# dbt Project Structure Reference & Configuring dbt for Microsoft Fabric

## Part 1 — What Every File and Folder Is For

```
oaktree_dbt/
├── dbt_project.yml       <- THE project config file (see Part 2 for full breakdown)
├── profiles.yml           <- WHERE dbt connects (local DuckDB today, Fabric later)
├── seeds/                 <- raw CSVs, loaded as-is by `dbt seed`
├── models/
│   ├── bronze/            <- thin staging views, no business logic
│   ├── silver/             <- cleaning/transformation logic
│   ├── gold/               <- reporting-ready, aggregated tables
│   └── schema.yml         <- descriptions + tests for seeds and models
├── snapshots/              <- dbt-native SCD2 (see the SCD2 lab thread)
├── macros/                 <- reusable SQL/Jinja, including custom generic tests
├── tests/                  <- singular tests (one-off SELECT-based assertions)
├── guides/                 <- this documentation (not a dbt-reserved folder name)
└── target/  (generated)    <- compiled SQL, run results — safe to delete anytime
```

### `seeds/` — Where Source Data Lives (For Local Practice)

Any CSV placed here becomes a real table when you run `dbt seed`. This
is exactly analogous to uploading a CSV into a Lakehouse's `Files/`
folder — except dbt manages the load for you, and reloading is just
`dbt seed` again.

**Update this when:** you're practicing locally and need to simulate a
new batch of source data (e.g., a new SCD2 update snapshot). **In
production against Fabric, seeds are rarely used for real source
data** — real sources are usually already-existing tables you point a
model at directly, or files ingested by a separate pipeline (ADF,
a notebook, a Dataflow Gen2). Seeds are primarily a local-development
and small-reference-table convenience.

### `models/` — Your Transformation Logic, One File Per Table

Every `.sql` file here is one model = one `SELECT` statement = one
table or view. The **folder structure inside `models/` is a naming
convention for humans and for `dbt_project.yml` config, not something
dbt requires** — you could technically put every model in one flat
folder, but organizing by layer (bronze/silver/gold) makes the project
navigable and lets you set different default materializations per
folder (see Part 2).

**Update these when:** the transformation logic itself changes — a new
column, a new business rule, a new aggregation grain.

### `models/schema.yml` — Descriptions and Tests, Not Transformation Logic

This file never transforms data — it only **describes and tests**
models and seeds that already exist as `.sql` files (or as seed CSVs).
Think of it as the YAML-based equivalent of writing docstrings plus
unit tests for your SQL.

**Update this when:** you add a new model/seed and want it documented
or tested, or when you're adding a new business rule that deserves an
explicit test (exactly like the `positive_value` test in Part 3 of the
Testing guide).

### `snapshots/` — dbt-Native SCD2

Each `.sql` file here is one snapshot, using the special
`{% snapshot %}...{% endsnapshot %}` block instead of a plain `SELECT`.
dbt manages `dbt_valid_from`, `dbt_valid_to`, and a surrogate key for
you — this is the automated version of the SCD2 logic built by hand
elsewhere in this program.

**Update these when:** a new dimension (or occasionally a fact, per the
trade amendment scenario) needs history tracking, and you want dbt to
manage the expire/insert logic instead of hand-rolling it.

### `macros/` — Reusable Jinja/SQL, Including Custom Generic Tests

Anything you'd otherwise copy-paste across multiple models belongs
here — a repeated CASE statement, a currency conversion snippet, or
(as in this project) a custom generic test like `positive_value` that
can be applied to any column by name.

**Update these when:** you notice the same logic appearing in two or
more models, or you want a new reusable test type.

### `tests/` — Singular, One-Off Tests

A `.sql` file here is a **singular test**: a plain `SELECT` statement
that should return zero rows. If it returns any rows, those rows are
the failures. Unlike a generic test (in `schema.yml`, reusable across
columns/models), a singular test is specific to one particular
business rule you want to assert, once.

**Update these when:** you have a one-off data quality assertion that
doesn't fit the "reusable across many columns" shape of a generic test
— e.g., "the sum of all Gold trade values should never differ from the
sum of all Silver trade values by more than a rounding tolerance."

### `target/` — Generated Output (Never Hand-Edit)

Created automatically every time you run any dbt command. Contains
compiled SQL (what your Jinja templates actually turned into),
`manifest.json` (the full project metadata dbt uses internally), and
run results. **Safe to delete at any time** — dbt regenerates it on the
next command. Most teams add this to `.gitignore`.

### `logs/` — dbt's Own Execution Logs

Also auto-generated, also safe to delete, also typically gitignored.
Useful when a command fails and the terminal output alone isn't
enough — `logs/dbt.log` has the full, unabridged detail.

---

## Part 2 — The `dbt_project.yml` File, Key by Key

```yaml
name: 'oaktree_dbt'          # the project's internal name — referenced
                              # nowhere externally, just an identifier
version: '1.0.0'              # your own version number for the project
config-version: 2              # dbt's config schema version — leave at 2

profile: 'oaktree_dbt'        # MUST match a profile name in profiles.yml
                                # — this is how dbt_project.yml and
                                # profiles.yml link together

model-paths: ["models"]        # where dbt looks for .sql model files
seed-paths: ["seeds"]           # where dbt looks for seed CSVs
test-paths: ["tests"]            # where dbt looks for singular tests
macro-paths: ["macros"]           # where dbt looks for macros/generic tests

target-path: "target"              # where compiled output goes
clean-targets:                       # what `dbt clean` deletes
  - "target"
  - "dbt_packages"

models:                                # PER-FOLDER default configuration
  oaktree_dbt:                          # must match the `name:` above
    bronze:
      +materialized: view                # Bronze models default to VIEW
    silver:
      +materialized: table                 # Silver models default to TABLE
    gold:
      +materialized: table                  # Gold models default to TABLE

seeds:
  oaktree_dbt:
    +schema: bronze                          # seeds land in a "bronze" schema
```

**Why views for Bronze but tables for Silver/Gold?** A view costs
nothing to keep up to date (it re-reads the underlying seed every
query) — appropriate for a thin staging layer with no real
transformation cost. Silver and Gold involve actual computation
(dedup, aggregation) that you don't want to re-run on every single
query, so materializing them as physical tables trades some staleness
risk for real query speed — you accept that they only reflect reality
as of the last `dbt run`.

**The `+` prefix** on `materialized`, `schema`, etc. is dbt's config
syntax — it means "apply this setting to every model in this
folder/subfolder," and any individual model can override it with its
own `{{ config(...) }}` block at the top of its `.sql` file.

---

## Part 3 — Configuring dbt for Microsoft Fabric

**A note on currency:** Microsoft's dbt-on-Fabric tooling is evolving
quickly — Microsoft has publicly stated a native Fabric Lakehouse dbt
adapter is coming, and a native "dbt job" Fabric item type is in
preview as of this writing. Treat the steps below as accurate for the
generally-available path today, and check
[Microsoft Learn's dbt setup tutorial](https://learn.microsoft.com/en-us/fabric/data-warehouse/tutorial-setup-dbt)
for anything that may have changed since.

### The Important Architectural Decision First

Your Gold tables from earlier sessions live as **Delta tables in a
Fabric Lakehouse**, written by Spark notebooks. There are two different
ways dbt can target Fabric, and they are NOT interchangeable:

| Target | Engine | Can dbt WRITE new tables here? |
|---|---|---|
| **Fabric Data Warehouse** (a separate Fabric item you create) | T-SQL | **Yes** — this is the officially supported, general-availability path |
| **Fabric Lakehouse SQL Analytics Endpoint** | T-SQL (read-only) | **No** — this endpoint auto-mirrors Spark-written Delta tables for reading only; dbt cannot create tables through it |
| **Fabric Lakehouse via Spark** (community adapter, `type: fabricspark`) | Spark SQL (via Livy) | **Yes** — this writes real Delta tables directly into the Lakehouse, closest to what your notebooks already do |

**Practical recommendation:** if you want dbt models to land in a
genuinely new place with minimal setup, target a **Fabric Warehouse**
item (Path A below) — it's Microsoft's own supported adapter and the
path documented on Microsoft Learn. If you specifically want dbt to
write into the **same Lakehouse** your notebooks already populate, you
need the Spark-based path (Path B below), which uses a
community-maintained adapter rather than Microsoft's own package.

### Path A — dbt Targeting a Fabric Data Warehouse (Recommended Default)

**Step 1 — Create a Fabric Warehouse item**

In your Fabric workspace: **+ New item → Warehouse**. Note its **SQL
connection string** (Warehouse settings → Connection strings).

**Step 2 — Install the adapter and ODBC driver**

```bash
pip install dbt-fabric
```

The adapter needs the Microsoft ODBC Driver for SQL Server installed
locally (Windows/macOS/Linux installers are linked from the
[dbt-fabric GitHub page](https://github.com/microsoft/dbt-fabric)). On
Debian/Ubuntu:
```bash
sudo apt-get install -y unixodbc-dev
```

**Step 3 — Authenticate to Azure**

```bash
az login
```

**Step 4 — Configure `profiles.yml`**

```yaml
oaktree_dbt:
  target: fabric-dev
  outputs:
    fabric-dev:
      type: fabric
      authentication: CLI
      driver: "ODBC Driver 18 for SQL Server"
      host: "<your-warehouse-SQL-connection-string>"
      database: "<your-warehouse-name>"
      schema: dbo
      threads: 4
```

**Step 5 — Run exactly the same commands**

```bash
dbt seed
dbt run
dbt test
```

Every model, test, and snapshot file from this project runs completely
unchanged — only `profiles.yml` changed.

**Known Fabric Data Warehouse limitations to watch for** (from the
adapter's own documentation): nested CTEs are not supported in model
SQL (rewrite as sequential CTEs or subqueries if needed), the
`ephemeral` materialization is unsupported, columns cannot have
`NOT NULL` or other constraints applied automatically, and indexes
configured in dbt are silently ignored (Fabric Warehouse doesn't
support them).

### Path B — dbt Targeting Your Existing Fabric Lakehouse (Spark)

This path writes directly into the same Lakehouse your notebooks
already use, via a community-maintained adapter that adds a
`fabricspark` connection type on top of the same `dbt-fabric` package
family:

```bash
pip install dbt-fabric-samdebruyn   # community adapter; verify current package name before use
```

```yaml
oaktree_dbt:
  target: dev
  outputs:
    dev:
      type: fabricspark
      # Livy/Spark session connection details for your Lakehouse —
      # consult the adapter's own documentation for the exact keys,
      # as this is a community project with its own release cadence
```

Because this targets Spark SQL rather than T-SQL, materializations and
behavior are closer to what you already saw in the Fabric notebooks
earlier in this program — including support for Python models, which
Fabric Data Warehouse (Path A) does not offer.

### Path C — The Native "dbt job" Fabric Item (Preview)

Microsoft Fabric now has a **dbt job** item type (in preview) — a
managed way to run dbt directly inside Fabric, without a local
`profiles.yml` or a separate machine running dbt at all. Create it via
**+ New item → dbt job** in your workspace, point it at your dbt
project (e.g., synced from Git), and Fabric handles the execution
environment and versioning for you. This is the direction Microsoft is
investing in most heavily — worth checking for updates before building
a long-term operational process around Path A or B.

### Recap: What Changes, What Doesn't

| | Local (this project, today) | Fabric Warehouse (Path A) | Fabric Lakehouse/Spark (Path B) |
|---|---|---|---|
| `profiles.yml` type | `duckdb` | `fabric` | `fabricspark` |
| Models/tests/snapshots | Unchanged | Unchanged | Unchanged |
| Where data lives | A local `.duckdb` file | A Fabric Warehouse | Your existing Fabric Lakehouse |
| Who maintains the adapter | dbt Labs (duckdb) | Microsoft | Community |

The entire point of this comparison: **the SQL you write today is not
throwaway practice code** — it's the same SQL that runs in production,
regardless of which path your organization ultimately chooses.

