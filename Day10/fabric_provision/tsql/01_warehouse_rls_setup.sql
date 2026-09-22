/* =====================================================================
   01_warehouse_rls_setup.sql
   ---------------------------------------------------------------------
   Implements Row-Level Security at the WAREHOUSE level using Fabric's
   native T-SQL CREATE SECURITY POLICY feature — run this against
   oaktree_trades_wh (the Warehouse created by the Fabric provisioning
   scripts), after gold_fact_trades_daily and gold_dim_trader already
   exist there (via dbt, a notebook, or a Copy Activity).

   IMPORTANT FABRIC-SPECIFIC NOTES (verified against current docs):
     - Fabric supports FILTER predicates only. BLOCK predicates
       (used to prevent bad INSERT/UPDATE in full SQL Server) are NOT
       supported in Fabric Data Warehouse.
     - This same pattern also works directly against a Lakehouse's
       auto-generated SQL analytics endpoint — you can't CREATE TABLE
       there, but you CAN CREATE SCHEMA, CREATE FUNCTION, and
       CREATE SECURITY POLICY on the existing tables.
   ===================================================================== */

-- 1. A dedicated schema for security objects (best practice: keeps
--    predicate functions/policies separate from your data schema)
CREATE SCHEMA Security;
GO

-- 2. The mapping between a real login and a trader_id. In production,
--    populate this from your actual Entra ID user list; the values
--    below are placeholders for practicing the pattern.
CREATE TABLE Security.trader_login_mapping (
    trader_id   INT           NOT NULL,
    login_name  VARCHAR(200)  NOT NULL   -- matches USER_NAME() / SUSER_SNAME()
);

INSERT INTO Security.trader_login_mapping (trader_id, login_name) VALUES
    (1, 'a.mehta@oaktree-example.com'),
    (2, 'r.iyer@oaktree-example.com'),
    (3, 's.kapoor@oaktree-example.com'),
    (4, 'n.rao@oaktree-example.com'),
    (5, 'p.sharma@oaktree-example.com'),
    (6, 'v.nair@oaktree-example.com');

-- 3. The security predicate — an inline table-valued function. This is
--    evaluated by the SQL engine on EVERY query against the protected
--    table(s), for whoever is actually connected (SUSER_SNAME()).
--    WITH SCHEMABINDING is the (recommended) default: it lets Fabric
--    skip a separate permission check on every query, at the cost of
--    needing to drop the policy before altering the underlying tables.
CREATE FUNCTION Security.tvf_trader_security_predicate(@trader_id AS INT)
RETURNS TABLE
WITH SCHEMABINDING
AS
RETURN
    SELECT 1 AS is_visible
    WHERE @trader_id IN (
        SELECT trader_id FROM Security.trader_login_mapping
        WHERE login_name = SUSER_SNAME()
    )
    OR USER_NAME() = 'compliance_admin'   -- an unrestricted, full-access identity
GO

-- 4. The security policy — binds the predicate function to the actual
--    tables it should filter. Add as many tables as need the same rule.
CREATE SECURITY POLICY Security.TraderRowFilter
    ADD FILTER PREDICATE Security.tvf_trader_security_predicate(trader_id)
    ON dbo.gold_fact_trades_daily,
    ADD FILTER PREDICATE Security.tvf_trader_security_predicate(trader_id)
    ON dbo.gold_dim_trader
    WITH (STATE = ON);
GO

/* ---------------------------------------------------------------------
   VERIFY: run this AS a specific login to see the filter in action.
   In Fabric, the simplest way to test different logins is to have a
   colleague (or a second Entra ID test account you control) connect
   and run this same query — RLS is enforced by the engine itself, not
   by anything in the query text, so there is no "run as" trick that
   works from a single elevated login the way it might in some other
   platforms.
   --------------------------------------------------------------------- */
SELECT trade_type, SUM(trade_value) AS total_value, COUNT(*) AS trades
FROM dbo.gold_fact_trades_daily
GROUP BY trade_type;

/* ---------------------------------------------------------------------
   TEARDOWN (if you need to remove this later):
   --------------------------------------------------------------------- */
-- ALTER SECURITY POLICY Security.TraderRowFilter WITH (STATE = OFF);
-- DROP SECURITY POLICY Security.TraderRowFilter;
-- DROP FUNCTION Security.tvf_trader_security_predicate;
-- DROP TABLE Security.trader_login_mapping;
-- DROP SCHEMA Security;
