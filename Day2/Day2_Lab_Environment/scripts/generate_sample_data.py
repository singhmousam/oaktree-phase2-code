"""
generate_sample_data.py
=======================
Generates the OakTree "trade blotter" sample dataset used across the training
program (Day 1 demo, Day 2 ADF lab source, Day 3 PySpark input, Day 4+ Fabric).

Produces three CSVs:
  - trade_blotter.csv    : the raw fact-like extract (what "Oracle" would export nightly)
  - dim_security.csv     : security reference/dimension data
  - dim_trader.csv       : trader reference/dimension data

Deliberately includes realistic messiness (duplicate rows from retried loads,
a handful of bad records with non-positive quantity/price) so the Day 2/3
data-quality and de-duplication logic has something real to clean.
"""
import csv
import random
from datetime import date, timedelta, datetime

random.seed(42)

OUT_DIR = "/home/claude/day2_lab/data"

# ---------------------------------------------------------------------
# Dimension data
# ---------------------------------------------------------------------
securities = [
    (1, "INFY",  "Infosys Ltd",          "Equity",       "Technology", "INR"),
    (2, "HDFCB", "HDFC Bank",            "Equity",       "Financials", "INR"),
    (3, "GS10Y", "10Y Govt Bond",        "Fixed Income", "Sovereign",  "INR"),
    (4, "TCS",   "Tata Consultancy Svc", "Equity",       "Technology", "INR"),
    (5, "RELI",  "Reliance Industries",  "Equity",       "Energy",     "INR"),
    (6, "ICICI", "ICICI Bank",           "Equity",       "Financials", "INR"),
    (7, "CORP5Y","5Y Corporate Bond",    "Fixed Income", "Corporate",  "INR"),
    (8, "SUZUK", "Maruti Suzuki",        "Equity",       "Auto",       "INR"),
]

traders = [
    (1, "A. Mehta",  "Equities", "APAC"),
    (2, "R. Iyer",   "Credit",   "APAC"),
    (3, "S. Kapoor", "Equities", "APAC"),
    (4, "N. Rao",    "Macro",    "APAC"),
    (5, "P. Sharma", "Credit",   "APAC"),
    (6, "V. Nair",   "Equities", "APAC"),
]

with open(f"{OUT_DIR}/dim_security.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["security_id", "ticker", "security_name", "asset_class", "sector", "currency"])
    w.writerows(securities)

with open(f"{OUT_DIR}/dim_trader.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["trader_id", "trader_name", "desk", "region"])
    w.writerows(traders)

# ---------------------------------------------------------------------
# Fact data: trade_blotter.csv
# ---------------------------------------------------------------------
start_date = date(2026, 5, 1)
num_business_days = 31  # covers May 2026, matching Day 1's sample query month

rows = []
trade_id = 100001

def is_business_day(d):
    return d.weekday() < 5  # Mon-Fri

d = start_date
business_days = []
while len(business_days) < num_business_days and d < start_date + timedelta(days=45):
    if is_business_day(d):
        business_days.append(d)
    d += timedelta(days=1)

for bday in business_days:
    num_trades_today = random.randint(12, 24)
    for _ in range(num_trades_today):
        sec = random.choice(securities)
        trd = random.choice(traders)
        trade_type = random.choice(["BUY", "SELL"])
        if sec[3] == "Fixed Income":
            qty = random.randint(10, 200) * 1000       # face value lots
            price = round(random.uniform(95, 105), 2)   # near par
        else:
            qty = random.randint(1, 50) * 100           # share lots
            price = round(random.uniform(150, 3200), 2)
        modified_ts = datetime.combine(bday, datetime.min.time()) + timedelta(
            hours=random.randint(9, 17), minutes=random.randint(0, 59))
        rows.append([
            trade_id, bday.isoformat(), sec[0], trd[0], trade_type, qty, price,
            modified_ts.strftime("%Y-%m-%d %H:%M:%S"),
        ])
        trade_id += 1

# --- Inject realistic messiness ---------------------------------------
# 1) Duplicate rows (simulating a retried/partially-failed load) — ~1.5% of rows
num_dupes = max(3, int(len(rows) * 0.015))
for _ in range(num_dupes):
    rows.append(random.choice(rows).copy())

# 2) A few bad records: non-positive quantity or price (data entry errors)
num_bad = max(3, int(len(rows) * 0.01))
for _ in range(num_bad):
    bad = random.choice(rows).copy()
    bad[0] = trade_id
    trade_id += 1
    if random.random() < 0.5:
        bad[5] = -abs(bad[5])   # negative quantity
    else:
        bad[6] = 0.0            # zero price
    rows.append(bad)

random.shuffle(rows)

with open(f"{OUT_DIR}/trade_blotter.csv", "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["trade_id", "trade_date", "security_id", "trader_id", "trade_type",
                "quantity", "price", "last_modified_ts"])
    w.writerows(rows)

print(f"Generated {len(rows)} trade_blotter rows across {len(business_days)} business days")
print(f"  - includes {num_dupes} duplicate rows and {num_bad} bad-data rows")
print(f"Files written to {OUT_DIR}/")
