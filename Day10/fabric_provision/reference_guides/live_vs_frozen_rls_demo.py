"""
live_vs_frozen_rls_demo.py
============================
Proves, with real code and real output, WHY Warehouse-level RLS reaches
some semantic model types but not others.

The core idea: a "live" connection (DirectQuery, or Direct Lake on SQL)
re-runs the security predicate EVERY time someone queries. A "frozen"
connection (Import mode) runs the predicate ONCE, at refresh time, using
one fixed identity -- and then serves that frozen copy to everyone
afterward, regardless of who's actually looking at the report.

We simulate this by:
  1. Defining a real, working "security predicate" function (the same
     shape as a T-SQL security predicate) against our trader data
  2. Simulating a LIVE query as trader_id=1, then trader_id=3
  3. Simulating an IMPORT: take ONE snapshot as a fixed "refresh identity"
     (typically an admin/service account with full access), then show
     that afterward, EVERY viewer of that imported copy sees the SAME
     data, regardless of who they are -- because the predicate never
     runs again after that one snapshot was taken

Run it:
    python3 live_vs_frozen_rls_demo.py
"""
import duckdb

con = duckdb.connect()

con.execute("CREATE TABLE dim_trader AS SELECT * FROM read_csv_auto('../data/dim_trader.csv')")
con.execute("""
    CREATE TABLE bronze_trades AS SELECT * FROM read_csv_auto('../data/trade_blotter.csv')
""")
con.execute("""
    CREATE TABLE silver_trades AS
    WITH deduped AS (
        SELECT *, ROW_NUMBER() OVER (PARTITION BY trade_id ORDER BY last_modified_ts DESC) AS rn
        FROM bronze_trades
    )
    SELECT trade_id, trade_date, security_id, trader_id, trade_type, quantity, price,
           ROUND(quantity * price, 2) AS trade_value
    FROM deduped WHERE rn = 1 AND quantity > 0 AND price > 0
""")


# =======================================================================
# THE SECURITY PREDICATE -- functionally identical to a T-SQL inline
# table-valued function used in CREATE SECURITY POLICY. In real Fabric,
# this predicate lives INSIDE the Warehouse and is evaluated by the SQL
# engine on every single query. Here, we call it explicitly to make that
# "evaluated every time" behavior visible.
# =======================================================================
def security_predicate(requesting_trader_id):
    """Returns the SQL WHERE clause a real T-SQL security predicate would
    apply for this requesting identity -- traders see only their own
    rows; None (Compliance/admin) sees everything."""
    if requesting_trader_id is None:
        return "1=1"   # unrestricted -- e.g. a Compliance/admin identity
    return f"trader_id = {requesting_trader_id}"


def live_query(requesting_trader_id):
    """Simulates DirectQuery / Direct Lake on SQL: the predicate is
    evaluated FRESH, for the REAL requesting identity, every time."""
    predicate = security_predicate(requesting_trader_id)
    return con.execute(f"""
        SELECT trade_type, SUM(trade_value) AS total_value, COUNT(*) AS trades
        FROM silver_trades
        WHERE {predicate}
        GROUP BY trade_type ORDER BY trade_type
    """).fetchdf()


print("=" * 78)
print("PART 1 -- LIVE QUERY MODE (DirectQuery / Direct Lake on SQL)")
print("The predicate re-runs for whoever is ACTUALLY asking, every time.")
print("=" * 78)

for trader_id, label in [(1, "Trader 1 (A. Mehta) asks"), (3, "Trader 3 (S. Kapoor) asks"), (None, "Compliance asks")]:
    result = live_query(trader_id)
    total = result["total_value"].sum()
    trades = result["trades"].sum()
    print(f"\n>>> {label}")
    print(f"    Predicate applied: {security_predicate(trader_id)}")
    print(f"    Result: {trades:.0f} trades, {total:,.2f} total value")

print("\n--> Notice: three different askers, three different, CORRECT answers.")
print("    This is what happens when RLS lives in the Warehouse and the")
print("    semantic model queries it live (DirectQuery, or Direct Lake on SQL,")
print("    which automatically falls back to DirectQuery specifically to")
print("    preserve this behavior).")


# =======================================================================
# PART 2 -- IMPORT MODE: ONE snapshot is taken, using ONE fixed identity
# (this is what actually happens during a scheduled refresh) -- and then
# EVERYONE who opens the report afterward sees that SAME frozen copy,
# regardless of who they are, because the predicate never runs again.
# =======================================================================
print("\n" + "=" * 78)
print("PART 2 -- IMPORT MODE")
print("The predicate runs ONCE, at refresh time, using ONE fixed identity.")
print("=" * 78)

REFRESH_IDENTITY = None   # Import refreshes typically run as a service
                            # account/admin with full access -- NOT as
                            # whichever end user later opens the report.
print(f"\n>>> Refresh happens now, using the refresh identity (predicate: "
      f"{security_predicate(REFRESH_IDENTITY)})")
imported_snapshot = live_query(REFRESH_IDENTITY)   # <-- this runs exactly ONCE
imported_total = imported_snapshot["total_value"].sum()
imported_trades = imported_snapshot["trades"].sum()
print(f"    Snapshot taken: {imported_trades:.0f} trades, {imported_total:,.2f} total value")
print("    This snapshot is now FROZEN into the semantic model's own storage.")

print("\n>>> Trader 1 (A. Mehta) opens the report built on this IMPORTED model:")
print(f"    Sees: {imported_trades:.0f} trades, {imported_total:,.2f} total value  <-- SAME as everyone else")

print("\n>>> Trader 3 (S. Kapoor) opens the SAME report:")
print(f"    Sees: {imported_trades:.0f} trades, {imported_total:,.2f} total value  <-- IDENTICAL, not filtered to them")

print("\n--> Notice: BOTH traders see the SAME (unrestricted) numbers, because")
print("    the predicate ran ONCE, using the refresh identity, and that frozen")
print("    result is all Import mode has to serve afterward. Warehouse RLS")
print("    genuinely cannot reach an Import-mode model -- this isn't a bug or")
print("    a misconfiguration, it's an inherent property of what 'Import' means.")
print("\n    THE FIX: define RLS again, separately, inside the semantic model")
print("    itself (Manage roles in Power BI Desktop) if you're using Import mode.")
