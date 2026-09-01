### Procedure Definition & Header

* **`CREATE OR ALTER PROCEDURE dbo.usp_transform_trades_to_silver`**: Creates the stored procedure or updates it if it already exists without losing underlying permissions.
* **`@WindowDate DATE`**: Input parameter defining the specific trading date process batch. This allows incremental processing (e.g., passing a date dynamically from an ADF pipeline parameter).
* **`SET NOCOUNT ON;`**: Suppresses the "(N rows affected)" messages sent back by SQL Server, saving network traffic and preventing pipeline runners like ADF from confusing row-count messages with query outputs.

---

### Step 1: De-duplication via Common Table Expression (CTE)

```sql
;WITH deduped AS (
    SELECT
        trade_id, trade_date, security_id, trader_id, trade_type, quantity, price,
        ROW_NUMBER() OVER (
            PARTITION BY trade_id
            ORDER BY last_modified_ts DESC
        ) AS rn
    FROM dbo.trade_blotter
    WHERE trade_date = @WindowDate
)

```

* **Target Source:** Queries raw data from the Bronze/staging table (`dbo.trade_blotter`) filtered to the target `@WindowDate`.
* **Windowing (`ROW_NUMBER()`):** Groups data by unique `trade_id` and assigns a sequential integer starting at 1 based on `last_modified_ts DESC`.
* **Outcome:** The most recently updated record for each `trade_id` gets `rn = 1`.

---

### Step 2: Quality Filtering & Data Transformation

```sql
SELECT
    trade_id, trade_date, security_id, trader_id, trade_type, quantity, price,
    CAST(quantity * price AS DECIMAL(18,2)) AS trade_value
FROM deduped
WHERE rn = 1
  AND quantity > 0
  AND price > 0

```

* **Deduplication:** `WHERE rn = 1` discards older duplicate records, keeping only the latest version of a trade.
* **Data Quality Checks:** Filters out invalid financial records (`quantity > 0` and `price > 0`).
* **Calculated Field:** Dynamically derives total monetary value (`quantity * price`) cast to `DECIMAL(18,2)` precision.

---

### Step 3: Atomic Upsert (`MERGE`) into Silver Table

```sql
MERGE dbo.trade_blotter_silver AS tgt
USING (...) AS src
ON tgt.trade_id = src.trade_id
WHEN MATCHED THEN ...
WHEN NOT MATCHED THEN ...

```

* **`ON tgt.trade_id = src.trade_id`**: Joins the cleaned source payload against the Silver layer table on primary trade key.
* **`WHEN MATCHED THEN UPDATE`**: Updates existing trades with newer values (`quantity`, `price`, `trade_value`) and attaches an audit timestamp (`SYSUTCDATETIME()`).
* **`WHEN NOT MATCHED THEN INSERT`**: Inserts entirely new trade records into the Silver table.

---

### Step 4: Summary Output for Pipeline Monitoring

```sql
SELECT
    @WindowDate AS window_date,
    (SELECT COUNT(*) FROM dbo.trade_blotter WHERE trade_date = @WindowDate) AS bronze_row_count,
    (SELECT COUNT(*) FROM dbo.trade_blotter_silver WHERE trade_date = @WindowDate) AS silver_row_count;

```

* Returns a single-row result set containing input parameters, total raw rows processed, and final loaded rows.
* **ADF Integration:** When invoked via the ADF Stored Procedure activity, this `SELECT` output becomes available in JSON format in the pipeline run output (`@activity('StoredProcedureStep').output.firstRow.silver_row_count`) for logging, monitoring, or conditional routing.