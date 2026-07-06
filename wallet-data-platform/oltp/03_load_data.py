"""
03_load_data.py
Loads the 7 CSV files into the PostgreSQL operational database.

Run:  python oltp/03_load_data.py --data-dir data

Notes:
  * The CSVs start with an invisible BOM character, so files are
    opened with encoding='utf-8-sig' to strip it.
  * Empty cells become SQL NULL.
  * Tables load parents-first (foreign key order).
  * Safe to re-run: tables are emptied first, and nothing is saved
    unless every table loads successfully (all-or-nothing).
"""

import argparse
import configparser
import sys
import time
from pathlib import Path

import psycopg2

PROJECT_ROOT = Path(__file__).resolve().parent.parent

# parents before children
LOAD_ORDER = [
    "customers",
    "accounts",
    "cards",
    "transactions",
    "purchase",
    "cashout",
    "transfers",
]


def load_table(cur, table, csv_path):
    copy_sql = f"COPY {table} FROM STDIN WITH (FORMAT csv, HEADER true, NULL '')"
    with open(csv_path, "r", encoding="utf-8-sig", newline="") as f:
        cur.copy_expert(copy_sql, f)
    cur.execute(f"SELECT count(*) FROM {table}")
    return cur.fetchone()[0]


def main():
    parser = argparse.ArgumentParser(description="Load CSVs into wallet_oltp")
    parser.add_argument("--data-dir", default="data")
    args = parser.parse_args()

    data_dir = Path(args.data_dir)
    missing = [t for t in LOAD_ORDER if not (data_dir / f"{t}.csv").exists()]
    if missing:
        print(f"ERROR: missing CSV files in '{data_dir}': {missing}")
        return 1

    creds = configparser.ConfigParser()
    creds.read(PROJECT_ROOT / "creds.ini")
    pg = creds["postgres"]

    conn = psycopg2.connect(
        host=pg["host"], port=int(pg["port"]), dbname=pg["database"],
        user=pg["user"], password=pg["password"],
    )
    conn.autocommit = False
    try:
        with conn.cursor() as cur:
            print("Truncating existing data ...")
            cur.execute("TRUNCATE TABLE " + ", ".join(LOAD_ORDER) + " CASCADE")
            for table in LOAD_ORDER:
                t0 = time.perf_counter()
                rows = load_table(cur, table, data_dir / f"{table}.csv")
                print(f"  {table:<13} {rows:>8,} rows  ({time.perf_counter() - t0:.1f}s)")
        conn.commit()
        print("Load complete.")
        return 0
    except Exception as exc:
        conn.rollback()
        print(f"LOAD FAILED, rolled back: {exc}")
        return 1
    finally:
        conn.close()


if __name__ == "__main__":
    sys.exit(main())
