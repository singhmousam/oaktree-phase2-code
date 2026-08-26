/* =====================================================================
   02_setup_source_database.sql
   ---------------------------------------------------------------------
   Run this against the Azure SQL Database created by 01_provision_infra.sh
   (via Azure Data Studio, SSMS, sqlcmd, or the Query Editor in the Azure
   Portal). It stands in for "the legacy Oracle trade blotter system" from
   the Day 1 case study — the exact source Day 2's ADF pipeline reads from.

   What this script does:
     1. Creates dbo.dim_security / dbo.dim_trader (reference data)
     2. Creates dbo.trade_blotter (the raw source table ADF will extract from)
     3. Creates dbo.trade_blotter_silver (the cleaned table ADF writes to)
     4. Creates usp_transform_trades_to_silver — the T-SQL stored procedure
        that IS the "transformation" step of today's ADF pipeline
     5. Seeds a quick-start sample of rows inline so the lab works even
        before the full CSV is bulk-loaded

   The full 567-row dataset lives in data/trade_blotter.csv — bulk-load it
   with the Azure Data Studio Import Wizard, bcp, or the BULK INSERT /
   OPENROWSET pattern documented at the bottom of this file.
   ===================================================================== */

-- 1. REFERENCE (DIMENSION) TABLES ---------------------------------------

IF OBJECT_ID('dbo.dim_security', 'U') IS NOT NULL DROP TABLE dbo.dim_security;
CREATE TABLE dbo.dim_security (
    security_id     INT             NOT NULL PRIMARY KEY,
    ticker          VARCHAR(20)     NOT NULL,
    security_name   VARCHAR(100)    NOT NULL,
    asset_class     VARCHAR(30)     NOT NULL,
    sector          VARCHAR(50)     NOT NULL,
    currency        CHAR(3)         NOT NULL
);

IF OBJECT_ID('dbo.dim_trader', 'U') IS NOT NULL DROP TABLE dbo.dim_trader;
CREATE TABLE dbo.dim_trader (
    trader_id       INT             NOT NULL PRIMARY KEY,
    trader_name     VARCHAR(50)     NOT NULL,
    desk            VARCHAR(30)     NOT NULL,
    region          VARCHAR(20)     NOT NULL
);

INSERT INTO dbo.dim_security (security_id, ticker, security_name, asset_class, sector, currency) VALUES
 (1, 'INFY',  'Infosys Ltd',           'Equity',       'Technology', 'INR'),
 (2, 'HDFCB', 'HDFC Bank',             'Equity',       'Financials', 'INR'),
 (3, 'GS10Y', '10Y Govt Bond',         'Fixed Income', 'Sovereign',  'INR'),
 (4, 'TCS',   'Tata Consultancy Svc',  'Equity',       'Technology', 'INR'),
 (5, 'RELI',  'Reliance Industries',   'Equity',       'Energy',     'INR'),
 (6, 'ICICI', 'ICICI Bank',            'Equity',       'Financials', 'INR'),
 (7, 'CORP5Y','5Y Corporate Bond',     'Fixed Income', 'Corporate',  'INR'),
 (8, 'SUZUK', 'Maruti Suzuki',         'Equity',       'Auto',       'INR');

INSERT INTO dbo.dim_trader (trader_id, trader_name, desk, region) VALUES
 (1, 'A. Mehta',  'Equities', 'APAC'),
 (2, 'R. Iyer',   'Credit',   'APAC'),
 (3, 'S. Kapoor', 'Equities', 'APAC'),
 (4, 'N. Rao',    'Macro',    'APAC'),
 (5, 'P. Sharma', 'Credit',   'APAC'),
 (6, 'V. Nair',   'Equities', 'APAC');

-- 2. SOURCE TABLE (the "Oracle" stand-in ADF extracts from) -------------

IF OBJECT_ID('dbo.trade_blotter', 'U') IS NOT NULL DROP TABLE dbo.trade_blotter;
CREATE TABLE dbo.trade_blotter (
    trade_id          BIGINT          NOT NULL PRIMARY KEY,
    trade_date        DATE            NOT NULL,
    security_id       INT             NOT NULL REFERENCES dbo.dim_security(security_id),
    trader_id         INT             NOT NULL REFERENCES dbo.dim_trader(trader_id),
    trade_type        VARCHAR(4)      NOT NULL,   -- BUY / SELL
    quantity          DECIMAL(18,2)   NOT NULL,
    price             DECIMAL(18,4)   NOT NULL,
    last_modified_ts  DATETIME2       NOT NULL DEFAULT SYSUTCDATETIME()
);
CREATE INDEX IX_trade_blotter_date ON dbo.trade_blotter(trade_date);

-- Quick-start sample (first ~20 rows) so the lab is functional immediately.
-- Bulk-load the remaining rows from data/trade_blotter.csv per the notes below.
INSERT INTO dbo.trade_blotter (trade_id, trade_date, security_id, trader_id, trade_type, quantity, price, last_modified_ts) VALUES
 (100001, '2026-05-01', 1, 1, 'BUY',  5000,  1550.25, '2026-05-01 10:12:00'),
 (100002, '2026-05-01', 2, 1, 'SELL', 2000,  1625.50, '2026-05-01 11:05:00'),
 (100003, '2026-05-01', 3, 2, 'BUY',  100000, 98.75,  '2026-05-01 09:47:00'),
 (100004, '2026-05-04', 1, 1, 'BUY',  1200,  1580.00, '2026-05-04 14:22:00'),
 (100005, '2026-05-04', 4, 3, 'SELL', 800,   3450.10, '2026-05-04 15:01:00'),
 (100006, '2026-05-04', 2, 1, 'SELL', 2000,  1625.50, '2026-05-04 11:06:00'),  -- intentional duplicate-style dupe of a diff day
 (100007, '2026-05-05', 5, 4, 'BUY',  1500,  2870.40, '2026-05-05 09:58:00'),
 (100008, '2026-05-05', 6, 6, 'BUY',  3000,  1105.20, '2026-05-05 13:14:00'),
 (100009, '2026-05-05', 7, 5, 'SELL', 50000, 101.10,  '2026-05-05 10:30:00'),
 (100010, '2026-05-06', 8, 3, 'BUY',  -400,  9800.00, '2026-05-06 12:00:00');  -- intentional bad record: negative quantity

/* 3. SILVER TABLE — what the ADF Stored Procedure Activity writes into ---
   Same grain as trade_blotter, but cleaned: deduplicated, non-positive
   quantity/price removed, and trade_value pre-computed. This is the exact
   Day 1 Medallion "Silver" concept, implemented here as a SQL table rather
   than a lake file — Day 2's final Copy Activity exports it to
   ADLS Gen2 silver/trades/ as Parquet for Day 3 (PySpark) and Day 4
   (Fabric) to pick up. */

IF OBJECT_ID('dbo.trade_blotter_silver', 'U') IS NOT NULL DROP TABLE dbo.trade_blotter_silver;
CREATE TABLE dbo.trade_blotter_silver (
    trade_id        BIGINT          NOT NULL PRIMARY KEY,
    trade_date      DATE            NOT NULL,
    security_id     INT             NOT NULL,
    trader_id       INT             NOT NULL,
    trade_type      VARCHAR(4)      NOT NULL,
    quantity        DECIMAL(18,2)   NOT NULL,
    price           DECIMAL(18,4)   NOT NULL,
    trade_value     DECIMAL(18,2)   NOT NULL,
    silver_loaded_ts DATETIME2      NOT NULL DEFAULT SYSUTCDATETIME()
);

-- 4. THE TRANSFORMATION — this stored procedure IS today's "Transform" step
GO
CREATE OR ALTER PROCEDURE dbo.usp_transform_trades_to_silver
    @WindowDate DATE
AS
BEGIN
    SET NOCOUNT ON;

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
    MERGE dbo.trade_blotter_silver AS tgt
    USING (
        SELECT
            trade_id, trade_date, security_id, trader_id, trade_type, quantity, price,
            CAST(quantity * price AS DECIMAL(18,2)) AS trade_value
        FROM deduped
        WHERE rn = 1                 -- de-duplication: keep latest version of each trade_id
          AND quantity > 0           -- data quality rule: reject non-positive quantity
          AND price > 0              -- data quality rule: reject non-positive price
    ) AS src
    ON tgt.trade_id = src.trade_id
    WHEN MATCHED THEN
        UPDATE SET quantity = src.quantity, price = src.price, trade_value = src.trade_value,
                   silver_loaded_ts = SYSUTCDATETIME()
    WHEN NOT MATCHED THEN
        INSERT (trade_id, trade_date, security_id, trader_id, trade_type, quantity, price, trade_value)
        VALUES (src.trade_id, src.trade_date, src.security_id, src.trader_id, src.trade_type, src.quantity, src.price, src.trade_value);

    -- Return a small summary row so the ADF Stored Procedure Activity's
    -- output can be inspected in the Monitoring Hub / pipeline run output.
    SELECT
        @WindowDate                                  AS window_date,
        (SELECT COUNT(*) FROM dbo.trade_blotter WHERE trade_date = @WindowDate)          AS bronze_row_count,
        (SELECT COUNT(*) FROM dbo.trade_blotter_silver WHERE trade_date = @WindowDate)   AS silver_row_count;
END
GO

/* ---------------------------------------------------------------------
   BULK-LOADING THE FULL 567-ROW SAMPLE (data/trade_blotter.csv)
   ---------------------------------------------------------------------
   Option A — Azure Data Studio: right-click the database > Import Wizard
             > point at trade_blotter.csv > map to dbo.trade_blotter.

   Option B — bcp command line (run from a machine with the file + bcp):
     bcp dbo.trade_blotter IN trade_blotter.csv -S <server>.database.windows.net
         -d <database> -U <admin_user> -P <password> -c -t"," -r"\n" -F 2

   Option C — OPENROWSET from a blob (if the CSV is uploaded to the
             landing container first — teaches the Day 2 audience the
             blob<->SQL bridge pattern used elsewhere in the platform):
     -- (requires a database-scoped credential + external data source
     --  pointing at the storage account container; see README for the
     --  full CREATE EXTERNAL DATA SOURCE snippet)

   Run whichever option fits the room's setup, then re-run the quick
   verification query below.
   --------------------------------------------------------------------- */

-- Verification query to run after loading (or right now against the seed rows):
SELECT trade_date, COUNT(*) AS row_count, SUM(quantity * price) AS gross_notional
FROM dbo.trade_blotter
GROUP BY trade_date
ORDER BY trade_date;
