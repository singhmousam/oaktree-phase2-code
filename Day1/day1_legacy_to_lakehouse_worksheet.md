# Day 1 Take-Home Worksheet — Legacy-to-Lakehouse Mapping
**Module 1: Data Architecture Core | Phase 2: Data Engineering & Microsoft Fabric**

## Part A — In-Class Case (recap)
Complete this in class using the OakTree Legacy Trade Reporting case brief.

| Legacy Component | Modern Lakehouse Equivalent | Medallion Layer | Azure/Fabric Tool | Security/Governance Note |
|---|---|---|---|---|
| Nightly Oracle trade blotter extract | | | | |
| 2 AM reconciliation SQL job | | | | |
| SSRS static PDF reports | | | | |
| No audit trail of report access | | | | |

## Part B — Take-Home Extension (due before Day 2)
Pick **two** additional legacy components common in your own environment (examples: a month-end batch job, a manual Excel reconciliation process, a shared network-drive report folder, a mainframe extract) and complete the same mapping.

| Legacy Component | Modern Lakehouse Equivalent | Medallion Layer | Azure/Fabric Tool | Security/Governance Note |
|---|---|---|---|---|
| | | | | |
| | | | | |

## Part C — Reflection (5 lines)
Where would confusing an OLTP system for an OLAP/reporting system cause a real production incident in your environment? Describe briefly.

_________________________________________________________________
_________________________________________________________________
_________________________________________________________________
_________________________________________________________________
_________________________________________________________________

## Part D — SQL Self-Check
Run `day1_star_schema_demo.sql` yourself (DuckDB — `pip install duckdb`, no server needed) and:
1. Add a new dimension table `dim_currency` (currency_key, currency_code, currency_name).
2. Add a `currency_key` column to `fact_trades` referencing it.
3. Re-run the analytical query, grouped additionally by currency.

Bring your results to Day 2 — we will reuse this schema when we build the Azure Data Factory pipeline.

---
*upGrad Enterprise · OakTree Capital Capability Development Program*
