# Assignment 2 — SCD2 Applied to Trade Data Itself

**Builds on:** the "Introducing Microsoft Fabric" lab you already completed
successfully. This assignment reuses your existing Lakehouse and
`silver_trades` table — no new environment setup needed.

## The Business Scenario

In Assignment 1, you applied SCD Type 2 to `dim_trader` — a reference
table that occasionally changes (a trader moves desks). That's the
textbook SCD2 use case.

Here's a harder, more realistic one: **the trade data itself sometimes
needs correcting.**

OakTree's middle office runs a trade reconciliation process roughly two
to three weeks after each trade date, comparing internal booking records
against the custodian's confirmations. This routinely surfaces a handful
of genuine errors:

- A quantity typo at booking (an extra zero — 900 shares instead of 90)
- A stale price used at execution, corrected once the official
  confirmation arrives
- A partial-fill mismatch between what the desk booked and what the
  broker actually confirms

When middle office confirms a correction, **the trade record must be
updated** — but whatever quantity and price were originally used to
generate a P&L report, a risk limit check, or a compliance filing on the
*original* date must still be reproducible exactly as it was. You cannot
simply overwrite the trade and move on.

**This is the same SCD2 pattern you already know — you're about to prove
it generalizes from a dimension table to a fact table.**

## Your Task

1. Open `assignment2_trade_amendments_STARTER.py` in your Fabric
   workspace (import it the same way you imported the original notebook).
2. Upload `trade_amendments_20260520.csv` into `Files/bronze/` in your
   Lakehouse.
3. Complete the four TODOs:
   - **TODO 1:** identify which `trade_id` values are being amended
   - **TODO 2:** expire the old (as-originally-booked) row for each
     amended trade — and make sure untouched trades are left alone
   - **TODO 3:** build the new, corrected current-version rows
   - **TODO 4:** union everything back together and save
4. Run the final `%%sql` cell and answer the reflection question in a
   markdown cell: what would a report from 2026-05-10 have shown for
   trade_id 100015, versus what the corrected book shows today — and
   why does a 10x quantity error matter more than a small price fix?

## What Success Looks Like

| Check | Expected Result |
|---|---|
| Row count before correction | 554 (same as `silver_trades`) |
| Row count after correction | 559 (5 trades × 1 new version each) |
| Trade 100015 history | 2 rows: quantity=900 (expired 2026-05-19) and quantity=90 (current) |
| Point-in-time query for 2026-05-10 | Returns the ORIGINAL, uncorrected values |
| Point-in-time query for today | Returns the CORRECTED values |

These are the exact numbers verified during development — if your
results differ, check that you're filtering on `is_current = True`
*before* comparing to the incoming amendment batch, not after.

## Stretch Goal (Optional)

The provided amendment batch only corrects 5 trades on a single date.
Real reconciliation cycles happen repeatedly. Create your own second
amendment file for a *different* batch date (e.g., `2026-06-15`),
including at least one trade that gets corrected **twice** (once in the
May batch, once in your new batch), and confirm your notebook correctly
produces a **three-row** history for that trade — exactly like the
`dim_trader` multi-version exercise from Assignment 1.

## Files in This Package

- `assignment2_trade_amendments_STARTER.py` — the notebook you'll complete
- `assignment2_trade_amendments_SOLUTION.py` — facilitator reference (don't peek early!)
- `trade_amendments_20260520.csv` — the correction batch
- This brief

## Why This Matters Beyond the Exercise

This pattern — versioned fact data, not just versioned dimensions — is
exactly what regulatory frameworks like MiFID II and Dodd-Frank expect
from trade reporting systems: a full, auditable history of every
correction, with the ability to reconstruct exactly what was known and
reported at any point in time. You've now built a working, simplified
version of that capability yourself.
