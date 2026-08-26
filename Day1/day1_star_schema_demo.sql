-- =====================================================================
-- DAY 1 LAB DEMO — Data Architecture Core
-- Star Schema Design: Trade Reporting Data Warehouse
-- Runs on: DuckDB / any ANSI-SQL engine (Azure Synapse, SQL Server, Snowflake)
-- =====================================================================

-- 1. DIMENSION TABLES ---------------------------------------------------

CREATE TABLE dim_date (
    date_key      INTEGER PRIMARY KEY,   -- e.g., 20260501
    full_date     DATE,
    day_name      VARCHAR,
    month_name    VARCHAR,
    quarter       INTEGER,
    year          INTEGER,
    is_month_end  BOOLEAN
);

CREATE TABLE dim_security (
    security_key   INTEGER PRIMARY KEY,
    ticker         VARCHAR,
    security_name  VARCHAR,
    asset_class    VARCHAR,     -- Equity, Fixed Income, Derivative
    sector         VARCHAR,
    currency       VARCHAR
);

CREATE TABLE dim_trader (
    trader_key     INTEGER PRIMARY KEY,
    trader_name    VARCHAR,
    desk           VARCHAR,     -- Equities, Credit, Macro
    region         VARCHAR
);

-- 2. FACT TABLE (grain: one row per executed trade) ---------------------

CREATE TABLE fact_trades (
    trade_id       BIGINT PRIMARY KEY,
    date_key       INTEGER REFERENCES dim_date(date_key),
    security_key   INTEGER REFERENCES dim_security(security_key),
    trader_key     INTEGER REFERENCES dim_trader(trader_key),
    trade_type     VARCHAR,     -- BUY / SELL
    quantity       DECIMAL(18,2),
    price          DECIMAL(18,4),
    trade_value    DECIMAL(18,2)   -- quantity * price, pre-computed measure
);

-- 3. SAMPLE DATA (small illustrative set for the live walkthrough) ------

INSERT INTO dim_date VALUES
 (20260501, '2026-05-01', 'Friday', 'May', 2, 2026, FALSE),
 (20260504, '2026-05-04', 'Monday', 'May', 2, 2026, FALSE),
 (20260529, '2026-05-29', 'Friday', 'May', 2, 2026, TRUE);

INSERT INTO dim_security VALUES
 (1, 'INFY', 'Infosys Ltd', 'Equity', 'Technology', 'INR'),
 (2, 'HDFCB', 'HDFC Bank', 'Equity', 'Financials', 'INR'),
 (3, 'GS10Y', '10Y Govt Bond', 'Fixed Income', 'Sovereign', 'INR');

INSERT INTO dim_trader VALUES
 (1, 'A. Mehta', 'Equities', 'APAC'),
 (2, 'R. Iyer',  'Credit',   'APAC');

INSERT INTO fact_trades VALUES
 (100001, 20260501, 1, 1, 'BUY',  5000,  1550.25, 5000*1550.25),
 (100002, 20260501, 2, 1, 'SELL', 2000,  1625.50, 2000*1625.50),
 (100003, 20260504, 3, 2, 'BUY',  100000, 98.75,  100000*98.75),
 (100004, 20260529, 1, 1, 'BUY',  1200,  1580.00, 1200*1580.00);

-- 4. ANALYTICAL QUERY — the payoff of a star schema ----------------------
-- "Total traded value by asset class, by month, buy vs sell"
-- Notice: no joins across more than 1 hop, business users read this instantly.

SELECT
    d.month_name,
    d.year,
    s.asset_class,
    f.trade_type,
    SUM(f.trade_value) AS total_traded_value,
    COUNT(*)            AS trade_count
FROM fact_trades f
JOIN dim_date     d ON f.date_key     = d.date_key
JOIN dim_security s ON f.security_key = s.security_key
GROUP BY d.month_name, d.year, s.asset_class, f.trade_type
ORDER BY total_traded_value DESC;

-- Expected discussion point in class:
-- This single GROUP BY query is what a "Gold layer" reporting table
-- or Power BI semantic model would expose to end users --
-- Day 4 (Fabric) and Day 6 (Unified Analytics) build on exactly this shape.
