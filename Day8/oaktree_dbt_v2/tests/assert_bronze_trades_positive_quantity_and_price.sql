-- SINGULAR TEST: every trade should have a positive quantity and a positive
-- price. Unlike a generic test (unique, not_null, accepted_values), a
-- singular test is just a plain SELECT statement living in tests/ -- if it
-- returns ANY rows, those rows are the failures, and the test fails.
--
-- This test intentionally targets BRONZE (stg_trade_blotter), not Silver.
-- Bronze is a faithful, unfiltered copy of the source -- so if the source
-- ever contains a negative quantity or a zero/negative price, THIS is where
-- you want to know about it immediately, not several layers downstream.
--
-- EXPECTED RESULT ON THIS PROGRAM'S SAMPLE DATA: this test FAILS, returning
-- 5 rows -- the same 5 intentionally-bad records described since Day 1's
-- sample data generator (negative quantity or zero price, simulating real
-- data-entry errors). That is correct, expected behavior for this dataset,
-- not a bug in the test.

select *
from {{ ref('stg_trade_blotter') }}
where quantity <= 0 or price <= 0
