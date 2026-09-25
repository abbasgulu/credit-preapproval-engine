"""Profile the Home Credit CSV files.

For every CSV: row count, column count, column names and the first data row.
The result is written to data/data_profile.txt (inside data/, so it is not
committed to git).

Run from the repository root:
    python python/scripts/check_data.py
"""
import csv
import os
import sys
import time

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
RAW = os.path.join(ROOT, "data", "raw")
OUT = os.path.join(ROOT, "data", "data_profile.txt")

FILES = [
    "application_train.csv",
    "application_test.csv",
    "bureau.csv",
    "bureau_balance.csv",
    "previous_application.csv",
    "installments_payments.csv",
    "POS_CASH_balance.csv",
    "credit_card_balance.csv",
    "HomeCredit_columns_description.csv",
]

# Expected row counts (excluding header) of the original Kaggle files
EXPECTED_ROWS = {
    "application_train.csv": 307_511,
    "application_test.csv": 48_744,
    "bureau.csv": 1_716_428,
    "bureau_balance.csv": 27_299_925,
    "previous_application.csv": 1_670_214,
    "installments_payments.csv": 13_605_401,
    "POS_CASH_balance.csv": 10_001_358,
    "credit_card_balance.csv": 3_840_312,
    "HomeCredit_columns_description.csv": 219,
}

csv.field_size_limit(min(sys.maxsize, 2**31 - 1))


def profile(path):
    # The description file is not UTF-8, so it is read as latin-1
    enc = "latin-1" if path.endswith("columns_description.csv") else "utf-8"
    with open(path, encoding=enc, newline="") as f:
        reader = csv.reader(f)
        header = next(reader)
        first = next(reader, [])
        rows = 1 if first else 0
        for _ in reader:
            rows += 1
    return header, first, rows


def main():
    lines, summary = [], []
    all_ok = True
    start_all = time.time()

    for name in FILES:
        path = os.path.join(RAW, name)
        if not os.path.exists(path):
            msg = f"{name:36} MISSING"
            summary.append(msg)
            print(msg)
            all_ok = False
            continue

        t0 = time.time()
        header, first, rows = profile(path)
        mb = os.path.getsize(path) / 1024 / 1024
        ok = rows == EXPECTED_ROWS[name]
        all_ok = all_ok and ok
        status = "OK" if ok else f"EXPECTED {EXPECTED_ROWS[name]:,}"
        row_line = (f"{name:36} {rows:>12,} rows {len(header):>4} cols "
                    f"{mb:>8.1f} MB  {status}")
        summary.append(row_line)
        print(f"{row_line}  ({time.time() - t0:.0f}s)")

        lines.append("=" * 90)
        lines.append(f"{name}  |  {rows:,} rows  |  {len(header)} columns")
        lines.append("=" * 90)
        for i, col in enumerate(header):
            val = first[i] if i < len(first) else ""
            lines.append(f"{i + 1:>4}. {col:40} {val}")
        lines.append("")

    with open(OUT, "w", encoding="utf-8") as f:
        f.write("SUMMARY\n")
        f.write("\n".join(summary))
        f.write("\n\n")
        f.write("\n".join(lines))

    print(f"\nWritten: {OUT}  ({time.time() - start_all:.0f}s)")
    print("ALL FILES OK" if all_ok else "SOME FILES DO NOT MATCH — see above")
    return 0 if all_ok else 1


if __name__ == "__main__":
    sys.exit(main())
